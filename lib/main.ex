defmodule CLI do
  def main(_args) do
    # CRITICAL: Set IO options BEFORE any output
    # This must happen first to configure stdin properly
    :io.setopts(:standard_io, [
      binary: true,
      encoding: :latin1,
      echo: false
    ])

    # Write prompt after IO is configured
    IO.write(:standard_error, "$ ")

    loop("", [], nil)
  end

  defp loop(current, history, cursor) do
    # Use :io.get_chars which should give us raw bytes
    ch = :io.get_chars(:standard_io, "", 1)

    case ch do
      <<byte>> ->
        handle_char(byte, current, history, cursor)

      :eof ->
        System.halt(0)

      _ ->
        loop(current, history, cursor)
    end
  end

  defp handle_char(ch, current, history, cursor) do
    cond do
      # Handle Enter - both \n and \r
      ch == ?\n or ch == ?\r ->
        # Echo newline to stderr to avoid interfering with test output
        IO.write(:standard_error, "\n")

        cmd = String.trim(current)

        if cmd != "" do
          execute_command(cmd)
          IO.write(:standard_error, "$ ")
          loop("", history ++ [cmd], nil)
        else
          IO.write(:standard_error, "$ ")
          loop("", history, nil)
        end

      ch == 27 ->
        # ESC - potential arrow key
        handle_escape(current, history, cursor)

      ch < 32 ->
        # Ignore other control characters
        loop(current, history, cursor)

      true ->
        # Regular character - don't echo, just add to buffer
        loop(current <> <<ch>>, history, nil)
    end
  end

  defp handle_escape(current, history, cursor) do
    # Read next byte
    byte1 = :io.get_chars(:standard_io, "", 1)

    case byte1 do
      <<91>> ->  # '[' is 91
        # Read third byte
        byte2 = :io.get_chars(:standard_io, "", 1)

        case byte2 do
          <<65>> ->  # 'A' is 65 - UP ARROW
            handle_up_arrow(current, history, cursor)

          _ ->
            loop(current, history, cursor)
        end

      _ ->
        loop(current, history, cursor)
    end
  end

  defp handle_up_arrow(current, history, cursor) do
    if history == [] do
      loop(current, history, cursor)
    else
      new_cursor =
        case cursor do
          nil -> length(history) - 1
          0 -> 0
          n -> n - 1
        end

      recalled = Enum.at(history, new_cursor)

      if recalled do
        # Clear current line on stderr
        for _ <- 1..String.length(current) do
          IO.write(:standard_error, "\b \b")
        end

        IO.write(:standard_error, recalled)
        loop(recalled, history, new_cursor)
      else
        loop(current, history, cursor)
      end
    end
  end

  defp execute_command("exit"), do: System.halt(0)

  defp execute_command("pwd") do
    IO.puts(File.cwd!())
  end

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
