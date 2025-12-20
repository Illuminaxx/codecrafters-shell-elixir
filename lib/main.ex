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
            args = String.replace_prefix(cmd, "echo ", "")
            IO.puts(args)
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

          # --- execution programme externe ---
          exec = find_executable(hd(String.split(cmd, " "))) ->
            parts = String.split(cmd, " ")
            command_name = hd(parts)
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

          true ->
            # Tous les autres cas => commande invalide
            IO.puts("#{cmd}: command not found")
            loop()
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
end
