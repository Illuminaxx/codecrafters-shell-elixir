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
            # Rien tapé, on relance juste la boucle
            loop()

          cmd === "exit" ->
            # On termine le programme: pas de nouveau prompt
            :ok

          String.starts_with?(cmd, "echo ") ->
            # Parser la redirection
            {cmd_without_redirect, output_file} = parse_redirection(cmd)

            # Extraire les arguments de echo
            input = String.replace_prefix(cmd_without_redirect, "echo ", "")
            args = parse_arguments(input)
            output = Enum.join(args, " ")

            # Afficher ou rediriger
            if output_file do
              File.write!(output_file, output <> "\n")
            else
              IO.puts(output)
            end

            loop()

          cmd === "echo" ->
            # Parser la redirection (pour "echo > file.txt")
            {_cmd, output_file} = parse_redirection(cmd)

            if output_file do
              File.write!(output_file, "\n")
            else
              IO.puts("")
            end

            loop()

          # --- pwd builting --- #
          cmd === "pwd" ->
            IO.puts(File.cwd!())
            loop()

          # --- cd builtin --- #
          String.starts_with?(cmd, "cd") ->
            path = String.replace_prefix(cmd, "cd ", "")

            # ~ remplacer par le repertoir HOME
            expanded_pth =
              cond do
                path === "~" ->
                  System.get_env("HOME") || "~"

                String.starts_with?(path, "~/") ->
                  home = System.get_env("HOME") || "~"
                  String.replace_prefix(path, "~", home)

                true ->
                  path
              end

            case File.cd(expanded_pth) do
              :ok ->
                loop()

              {:error, _reason} ->
                IO.puts("cd: #{path}: No such file or directory")
                loop()
            end

          # ---- type builtin ----
          String.starts_with?(cmd, "type ") ->
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

            loop()

          # --- execution programme externe --- #
          true ->
            # Parser la redirection si présente
            {cmd_without_redirect, output_file} = parse_redirection(cmd)

            # Parser la commande en tenant compte des quotes
            parts = parse_arguments(cmd_without_redirect)

            if parts == [] do
              loop()
            else
              command_name = hd(parts)

              case find_executable(command_name) do
                nil ->
                  IO.puts("#{cmd}: command not found")
                  loop()

                exec ->
                  args = tl(parts)

                  # Préparer les options du port
                  port_opts = [
                    {:arg0, to_charlist(command_name)},
                    {:args, Enum.map(args, &to_charlist/1)},
                    :binary,
                    :exit_status,
                    {:line, 1024}
                  ]

                  port = :erlang.open_port({:spawn_executable, to_charlist(exec)}, port_opts)

                  # Recevoir et rediriger la sortie
                  receive_and_redirect_output(port, output_file)
                  loop()
              end
            end
        end
    end
  end

  # --- Recherche PATH minimaliste ---
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

  # --- Recevoir l'output d'un port --- #
  defp receive_and_redirect_output(port, nil) do
    # Pas de redirection, afficher normalement
    receive do
      {^port, {:data, {:eol, line}}} ->
        IO.puts(line)
        receive_and_redirect_output(port, nil)

      {^port, {:exit_status, _status}} ->
        :ok
    end
  end

  defp receive_and_redirect_output(port, filename) do
    # Avec redirection, collecter toute la sortie
    output = collect_output(port, [])

    # Écrire dans le fichier
    File.write!(filename, Enum.join(output, "\n") <> if(output != [], do: "\n", else: ""))
  end

  # Collecter toute la sortie du port
  defp collect_output(port, acc) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        collect_output(port, [line | acc])

      {^port, {:exit_status, _status}} ->
        Enum.reverse(acc)
    end
  end

  # --- Parser pour gérer les single et double quotes + backslash ---
  defp parse_arguments(input) do
    parse_args(input, "", [], :none)
  end

  defp parse_args("", current, acc, _quote_type) do
    # Fin de l'input
    if current != "" do
      Enum.reverse([current | acc])
    else
      Enum.reverse(acc)
    end
  end

  # Début d'une single quote (si pas déjà dans des quotes)
  defp parse_args("'" <> rest, current, acc, :none) do
    parse_args(rest, current, acc, :single)
  end

  # Fin d'une single quote
  defp parse_args("'" <> rest, current, acc, :single) do
    parse_args(rest, current, acc, :none)
  end

  # Début d'une double quote (si pas déjà dans des quotes)
  defp parse_args("\"" <> rest, current, acc, :none) do
    parse_args(rest, current, acc, :double)
  end

  # Fin d'une double quote
  defp parse_args("\"" <> rest, current, acc, :double) do
    parse_args(rest, current, acc, :none)
  end

  # NOUVEAU : Backslash dans DOUBLE quotes - échappe " et \
  defp parse_args("\\" <> <<char::utf8, rest::binary>>, current, acc, :double)
       when char in [?", ?\\] do
    # char in [?", ?\\] signifie char == ?" (34) ou char == ?\\ (92)
    # On ajoute le caractère échappé sans le backslash
    parse_args(rest, current <> <<char::utf8>>, acc, :double)
  end

  # NOUVEAU : Backslash dans DOUBLE quotes - pour les autres caractères, le backslash reste littéral
  defp parse_args("\\" <> <<char::utf8, rest::binary>>, current, acc, :double) do
    # Pour \n, \t, etc. : on garde le backslash ET le caractère
    parse_args(rest, current <> "\\" <> <<char::utf8>>, acc, :double)
  end

  # Backslash HORS des quotes (échappement)
  defp parse_args("\\" <> <<char::utf8, rest::binary>>, current, acc, :none) do
    # Le backslash échappe le caractère suivant
    # On ajoute le caractère échappé (sans le backslash) à current
    parse_args(rest, current <> <<char::utf8>>, acc, :none)
  end

  # Caractère quelconque DANS des single quotes
  defp parse_args(<<char::utf8, rest::binary>>, current, acc, :single) do
    parse_args(rest, current <> <<char::utf8>>, acc, :single)
  end

  # Caractère quelconque DANS des double quotes
  defp parse_args(<<char::utf8, rest::binary>>, current, acc, :double) do
    parse_args(rest, current <> <<char::utf8>>, acc, :double)
  end

  # Espace HORS des quotes avec current vide : on ignore
  defp parse_args(" " <> rest, "", acc, :none) do
    parse_args(rest, "", acc, :none)
  end

  # Espace HORS des quotes : on termine l'argument actuel
  defp parse_args(" " <> rest, current, acc, :none) do
    parse_args(rest, "", [current | acc], :none)
  end

  # Caractère normal HORS des quotes
  defp parse_args(<<char::utf8, rest::binary>>, current, acc, :none) do
    parse_args(rest, current <> <<char::utf8>>, acc, :none)
  end

  # --- Parser la redirection de sortie ---
  defp parse_redirection(cmd) do
    case Regex.run(~r/\s+1?>/, cmd) do
      # Pas de redirection
      nil ->
        {cmd, nil}

      [redirect_op] ->
        # Séparer la commande et le fichier
        [before, after_redirect] = String.split(cmd, redirect_op, parts: 2)
        filename_parts = parse_arguments(String.trim(after_redirect))
        filename = if filename_parts != [], do: hd(filename_parts), else: nil
        {String.trim(before), filename}
    end
  end
end
