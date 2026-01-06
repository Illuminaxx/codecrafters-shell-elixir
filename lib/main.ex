defmodule CLI do
  def main(_args) do
    # Open stdin as a raw file descriptor
    {:ok, stdin} = :file.open(:standard_io, [:read, :binary, {:encoding, :latin1}])

    IO.write("$ ")
    loop("", [], nil, stdin)
  end

  defp loop(current, history, cursor, stdin) do
    # Read one byte at a time using file:read
    case :file.read(stdin, 1) do
      {:ok, <<byte>>} ->
        handle_char(byte, current, history, cursor, stdin)

      :eof ->
        System.halt(0)

      {:error, _} ->
        loop(current, history, cursor, stdin)
    end
  end

  defp handle_char(ch, current, history, cursor, stdin) do
    cond do
      # Handle both \n (cooked) and \r (raw) for Enter
      ch == ?\n or ch == ?\r ->
        cmd = String.trim(current)

        if cmd != "" do
          execute_command(cmd)
          IO.write("$ ")
          loop("", history ++ [cmd], nil, stdin)
        else
          IO.write("$ ")
          loop("", history, nil, stdin)
        end

      ch == 27 ->
        handle_escape(current, history, cursor, stdin)

      ch < 32 ->
        loop(current, history, cursor, stdin)

      true ->
        loop(current <> <<ch>>, history, nil, stdin)
    end
  end

  defp handle_escape(current, history, cursor, stdin) do
    # Read the next byte after ESC
    case :file.read(stdin, 1) do
      {:ok, <<91>>} ->  # '[' is 91
        # Read the third byte
        case :file.read(stdin, 1) do
          {:ok, <<65>>} ->  # 'A' is 65
            handle_up_arrow(current, history, cursor, stdin)

          _ ->
            loop(current, history, cursor, stdin)
        end

      _ ->
        loop(current, history, cursor, stdin)
    end
  end

  defp handle_up_arrow(current, history, cursor, stdin) do
    if history == [] do
      loop(current, history, cursor, stdin)
    else
      new_cursor =
        case cursor do
          nil -> length(history) - 1
          0 -> 0
          n -> n - 1
        end

      recalled = Enum.at(history, new_cursor)

      if recalled do
        # Clear current line
        for _ <- 1..String.length(current) do
          IO.write("\b \b")
        end

        IO.write(recalled)
        loop(recalled, history, new_cursor, stdin)
      else
        loop(current, history, cursor, stdin)
      end
    end
  end

  defp execute_command("exit"), do: System.halt(0)
  defp execute_command("pwd"), do: IO.puts(File.cwd!())

  defp execute_command(cmd) do
    case String.split(cmd) do
      ["echo" | rest] ->
        IO.puts(Enum.join(rest, " "))

      [command | args] ->
        case System.find_executable(command) do
          nil ->
            IO.puts("#{command}: command not found")

          exec ->
            {out, _} = System.cmd(exec, args, stderr_to_stdout: true)
            IO.write(out)
            unless String.ends_with?(out, "\n") do
              IO.write("\n")
            end
        end

      [] ->
        :ok
    end
  end
end
