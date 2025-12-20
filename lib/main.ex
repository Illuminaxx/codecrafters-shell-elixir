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

          cmd === "echo" ->
            IO.puts("")
            loop()

          String.starts_with?(cmd, "echo ") ->
            # On recupère tout ce qui vient apres "echo "
            input = String.replace_prefix(cmd, "echo ", "")
            args = parse_arguments(input)

            output = Enum.join(args, " ")
            IO.puts(output)
            loop()


          # --- pwd builting --- #
          cmd === "pwd" ->
            IO.puts(File.cwd!())
            loop()


          # --- cd builtin --- #
          String.starts_with?(cmd, "cd") ->
            path = String.replace_prefix(cmd, "cd ", "")

            # ~ remplacer par le repertoir HOME
            expanded_pth = cond do
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
  # Parser la commande en tenant compte des quotes
  parts = parse_arguments(cmd)

  if parts == [] do
    # Rien à faire
    loop()
  else
    command_name = hd(parts)

    # Chercher l'exécutable
    case find_executable(command_name) do
      nil ->
        # Pas trouvé
        IO.puts("#{cmd}: command not found")
        loop()

      exec ->
        # Trouvé ! On l'exécute
        args = tl(parts)

        port =
          :erlang.open_port(
            {:spawn_executable, to_charlist(exec)},
            [
              {:arg0, to_charlist(command_name)},
              {:args, Enum.map(args, &to_charlist/1)},
              :binary,
              :exit_status,
              {:line, 1024}
            ]
          )

        receive_port_opt(port)
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
  defp receive_port_opt(port) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        IO.puts(line)
        receive_port_opt(port)

      {^port, {:exit_status, _status}} ->
        :ok
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

# NOUVEAU : Backslash HORS des quotes (échappement)
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
end
