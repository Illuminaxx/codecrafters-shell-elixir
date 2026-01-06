defmodule CLI do
  def main(_args) do
    # Try to save original terminal settings
    original_settings =
      case System.cmd("sh", ["-c", "stty -g 2>/dev/null"], stderr_to_stdout: true) do
        {settings, 0} -> String.trim(settings)
        _ -> nil  # Not a terminal, can't save settings
      end

    # Put terminal in raw mode with -echo
    raw_mode =
      case System.cmd("sh", ["-c", "stty raw -echo 2>/dev/null"], stderr_to_stdout: true) do
        {_, 0} -> true
        _ -> false  # Not in raw mode
      end

    # Configure IO options - disable echo at Erlang level too
    :io.setopts(:standard_io, binary: true, encoding: :latin1, echo: false)

    IO.write("$ ")

    # Ensure terminal is restored on exit
    try do
      loop("", [], nil, raw_mode)
    after
      # Restore original terminal settings if we saved them
      if original_settings do
        System.cmd("sh", ["-c", "stty #{original_settings} 2>/dev/null"], stderr_to_stdout: true)
      end
    end
  end

  defp loop(current, history, cursor, raw_mode) do
    ch = :io.get_chars("", 1)
    case ch do
      <<byte>> -> handle_char(byte, current, history, cursor, raw_mode)
      _ -> loop(current, history, cursor, raw_mode)
    end
  end

  defp handle_char(ch, current, history, cursor, raw_mode) do
    cond do
      # In raw mode, Enter key sends \r (carriage return)
      ch == ?\n or ch == ?\r ->
        if raw_mode, do: IO.write("\r\n")
        cmd = String.trim(current)

        if cmd != "" do
          execute_command(cmd)
          IO.write("$ ")
          loop("", history ++ [cmd], nil, raw_mode)
        else
          IO.write("$ ")
          loop("", history, nil, raw_mode)
        end

      ch == 27 ->
        handle_escape(current, history, cursor, raw_mode)

      ch < 32 ->
        loop(current, history, cursor, raw_mode)

      true ->
        # Only echo if in raw mode (otherwise terminal does it automatically)
        if raw_mode, do: IO.write(<<ch>>)
        loop(current <> <<ch>>, history, nil, raw_mode)
    end
  end

  defp handle_escape(current, history, cursor, raw_mode) do
    # Read the next byte after ESC
    byte1 = :io.get_chars("", 1)
    case byte1 do
      <<91>> ->  # '[' is 91
        # Read the third byte
        byte2 = :io.get_chars("", 1)
        case byte2 do
          <<65>> ->  # 'A' is 65
            handle_up_arrow(current, history, cursor, raw_mode)

          _ ->
            # Unexpected sequence, ignore
            loop(current, history, cursor, raw_mode)
        end

      _ ->
        # Not an arrow key sequence, ignore
        loop(current, history, cursor, raw_mode)
    end
  end

  defp handle_up_arrow(current, history, cursor, raw_mode) do
    if history == [] do
      loop(current, history, cursor, raw_mode)
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
        loop(recalled, history, new_cursor, raw_mode)
      else
        loop(current, history, cursor, raw_mode)
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
