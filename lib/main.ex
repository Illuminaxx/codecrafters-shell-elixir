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

          # ---- type builtin ----
          String.starts_with?(cmd, "type ") ->
            arg = String.replace_prefix(cmd, "type ", "")
            builtin? = arg in ["echo", "exit", "type"]

            cond do
              builtin? ->
                IO.puts("#{arg} is a shell builtin")

              exec = find_executable(arg) ->
                IO.puts("#{arg} is #{exec}")

              true ->
                IO.puts("#{arg}: not found")
            end

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
end
