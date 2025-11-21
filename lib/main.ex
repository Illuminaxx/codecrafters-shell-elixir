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

        # Dans ce stage 2 : TOUT est invalid command
        unless cmd == "" do
          IO.puts("#{cmd}: command not found")
        end

        loop()
    end
  end
end
