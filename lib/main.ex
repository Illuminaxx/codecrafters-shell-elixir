defmodule CLI do
  def main(_args) do
    # Enable raw mode using NIF
    case TTY.enable_raw_mode() do
      :ok -> :ok
      {:error, _reason} -> :ok  # Continue even if raw mode fails
    end

    # Configure IO for binary input
    :io.setopts(:standard_io, binary: true, encoding: :latin1)

    IO.write("$ ")

    try do
      loop("", [], nil)
    after
      # Restore terminal on exit
      TTY.disable_raw_mode()
    end
  end

  defp loop(current, history, cursor) do
    ch = :io.get_chars("", 1)
    case ch do
      <<byte>> -> handle_char(byte, current, history, cursor)
      _ -> loop(current, history, cursor)
    end
  end

  defp handle_char(ch, current, history, cursor) do
    cond do
      # In raw mode, Enter sends \r (13), in cooked mode it sends \n (10)
      ch == ?\n or ch == ?\r ->
        # Echo newline in raw mode
        if ch == ?\r, do: IO.write("\r\n")

        cmd = String.trim(current)

        if cmd != "" do
          execute_command(cmd)
          IO.write("$ ")
          loop("", history ++ [cmd], nil)
        else
          IO.write("$ ")
          loop("", history, nil)
        end

      ch == 27 ->
        handle_escape(current, history, cursor)

      ch < 32 ->
        loop(current, history, cursor)

      true ->
        # Echo the character in raw mode
        IO.write(<<ch>>)
        loop(current <> <<ch>>, history, nil)
    end
  end

  defp handle_escape(current, history, cursor) do
    # Read the next byte after ESC
    byte1 = :io.get_chars("", 1)
    case byte1 do
      <<91>> ->  # '[' is 91
        # Read the third byte
        byte2 = :io.get_chars("", 1)
        case byte2 do
          <<65>> ->  # 'A' is 65
            handle_up_arrow(current, history, cursor)

          _ ->
            # Unexpected sequence, ignore
            loop(current, history, cursor)
        end

      _ ->
        # Not an arrow key sequence, ignore
        loop(current, history, cursor)
    end
  end

  defp handle_up_arrow(current, history, cursor) do
    if history == [] do
      loop(current, history, cursor)
    else
      # Calculate new cursor position
      new_cursor =
        case cursor do
          nil -> length(history) - 1
          0 -> 0
          n -> n - 1
        end

      recalled = Enum.at(history, new_cursor)

      if recalled do
        # Clear current line: \b \b for each character
        for _ <- 1..String.length(current) do
          IO.write("\b \b")
        end

        # Print the recalled command
        IO.write(recalled)
        loop(recalled, history, new_cursor)
      else
        loop(current, history, cursor)
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
            # Ensure newline if external command didn't print one
            unless String.ends_with?(out, "\n") do
              IO.write("\n")
            end
        end

      [] ->
        :ok
    end
  end
end
