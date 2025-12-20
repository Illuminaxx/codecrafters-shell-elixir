defmodule CLI do
  import Bitwise

  def main(_args) do
    loop()
  end

  defp loop do
    IO.write("$ ")

    case IO.read(:line) do
      :eof ->
        :ok

      {:error, _reason} ->
        :ok

      line ->
        cmd = String.trim(line)

        cond do
          cmd === "" ->
            loop()

          cmd === "exit" ->
            :ok

          String.starts_with?(cmd, "echo ") ->
            handle_echo_command(cmd)
            loop()

          cmd === "echo" ->
            handle_echo_empty(cmd)
            loop()

          cmd === "pwd" ->
            IO.puts(File.cwd!())
            loop()

          String.starts_with?(cmd, "cd ") ->
            handle_cd_command(cmd)
            loop()

          String.starts_with?(cmd, "type ") ->
            handle_type_command(cmd)
            loop()

          true ->
            handle_external_command(cmd)
            loop()
        end
    end
  end

  # --- Gestion de la commande echo ---
  defp handle_echo_command(cmd) do
    # Si la commande contient des redirections, utiliser un shell
    if String.contains?(cmd, ">") do
      execute_via_shell(cmd)
    else
      input = String.replace_prefix(cmd, "echo ", "")
      args = parse_arguments(input)
      output = Enum.join(args, " ")
      IO.puts(output)
    end
  end

  defp handle_echo_empty(cmd) do
    if String.contains?(cmd, ">") do
      execute_via_shell(cmd)
    else
      IO.puts("")
    end
  end

  # --- Gestion de la commande cd ---
  defp handle_cd_command(cmd) do
    path = String.replace_prefix(cmd, "cd ", "")

    expanded_path =
      cond do
        path === "~" ->
          System.get_env("HOME") || "~"

        String.starts_with?(path, "~/") ->
          home = System.get_env("HOME") || "~"
          String.replace_prefix(path, "~", home)

        true ->
          path
      end

    case File.cd(expanded_path) do
      :ok ->
        :ok

      {:error, _reason} ->
        IO.puts("cd: #{path}: No such file or directory")
    end
  end

  # --- Gestion de la commande type ---
  defp handle_type_command(cmd) do
    arg = String.replace_prefix(cmd, "type ", "")
    builtin? = arg in ["echo", "exit", "type", "pwd", "cd"]

    cond do
      builtin? ->
        IO.puts("#{arg} is a shell builtin")

      exec = find_executable(arg) ->
        IO.puts("#{arg} is #{exec}")

      true ->
        IO.puts("#{arg}: not found")
    end
  end

  # --- Gestion des commandes externes ---
  defp handle_external_command(cmd) do
    # Si la commande contient des redirections, utiliser un shell
    if String.contains?(cmd, ">") do
      execute_via_shell(cmd)
    else
      execute_direct(cmd)
    end
  end

  # Exécuter via /bin/sh pour gérer les redirections
  defp execute_via_shell(cmd) do
    port =
      :erlang.open_port(
        {:spawn, to_charlist("sh -c " <> shell_quote(cmd))},
        [:binary, :exit_status, {:line, 1024}]
      )

    receive_output(port)
  end

  # Exécuter directement sans passer par un shell
  defp execute_direct(cmd) do
    parts = parse_arguments(cmd)

    if parts == [] do
      :ok
    else
      command_name = hd(parts)

      case find_executable(command_name) do
        nil ->
          IO.puts("#{cmd}: command not found")

        exec ->
          args = tl(parts)

          port_opts = [
            {:arg0, to_charlist(command_name)},
            {:args, Enum.map(args, &to_charlist/1)},
            :binary,
            :exit_status,
            {:line, 1024}
          ]

          port = :erlang.open_port({:spawn_executable, to_charlist(exec)}, port_opts)
          receive_output(port)
      end
    end
  end

  # Recevoir et afficher la sortie d'un port
  defp receive_output(port) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        IO.puts(line)
        receive_output(port)

      {^port, {:exit_status, _status}} ->
        :ok
    end
  end

  # Échapper une commande pour sh -c
  defp shell_quote(cmd) do
    # Remplacer les ' par '\'' pour échapper correctement
    "'" <> String.replace(cmd, "'", "'\\''") <> "'"
  end

  # --- Recherche PATH ---
  defp find_executable(cmd) do
    path = System.get_env("PATH") || ""
    dirs = String.split(path, ":")

    Enum.find_value(dirs, fn dir ->
      candidate = Path.join(dir, cmd)

      if File.exists?(candidate) do
        case File.stat(candidate) do
          {:ok, %File.Stat{mode: mode}} ->
            if (mode &&& 0o111) != 0 do
              candidate
            else
              false
            end

          _ ->
            false
        end
      else
        false
      end
    end)
  end

  # --- Parser pour gérer les single et double quotes + backslash ---
  defp parse_arguments(input) do
    parse_args(input, "", [], :none)
  end

  defp parse_args("", current, acc, _quote_type) do
    if current != "" do
      Enum.reverse([current | acc])
    else
      Enum.reverse(acc)
    end
  end

  # Single quotes
  defp parse_args("'" <> rest, current, acc, :none) do
    parse_args(rest, current, acc, :single)
  end

  defp parse_args("'" <> rest, current, acc, :single) do
    parse_args(rest, current, acc, :none)
  end

  # Double quotes
  defp parse_args("\"" <> rest, current, acc, :none) do
    parse_args(rest, current, acc, :double)
  end

  defp parse_args("\"" <> rest, current, acc, :double) do
    parse_args(rest, current, acc, :none)
  end

  # Backslash dans double quotes - échappe " et \
  defp parse_args("\\" <> <<char::utf8, rest::binary>>, current, acc, :double)
       when char in [?", ?\\] do
    parse_args(rest, current <> <<char::utf8>>, acc, :double)
  end

  # Backslash dans double quotes - autres caractères restent littéraux
  defp parse_args("\\" <> <<char::utf8, rest::binary>>, current, acc, :double) do
    parse_args(rest, current <> "\\" <> <<char::utf8>>, acc, :double)
  end

  # Backslash hors quotes - échappement
  defp parse_args("\\" <> <<char::utf8, rest::binary>>, current, acc, :none) do
    parse_args(rest, current <> <<char::utf8>>, acc, :none)
  end

  # Caractères dans single quotes
  defp parse_args(<<char::utf8, rest::binary>>, current, acc, :single) do
    parse_args(rest, current <> <<char::utf8>>, acc, :single)
  end

  # Caractères dans double quotes
  defp parse_args(<<char::utf8, rest::binary>>, current, acc, :double) do
    parse_args(rest, current <> <<char::utf8>>, acc, :double)
  end

  # Espaces hors quotes
  defp parse_args(" " <> rest, "", acc, :none) do
    parse_args(rest, "", acc, :none)
  end

  defp parse_args(" " <> rest, current, acc, :none) do
    parse_args(rest, "", [current | acc], :none)
  end

  # Caractères normaux hors quotes
  defp parse_args(<<char::utf8, rest::binary>>, current, acc, :none) do
    parse_args(rest, current <> <<char::utf8>>, acc, :none)
  end
end
