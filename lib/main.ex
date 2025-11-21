defmodule CLI do
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

            if builtin? do
              IO.puts("#{arg} is a shell builtin")
            else
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
end
