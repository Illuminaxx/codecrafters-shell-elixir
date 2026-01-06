defmodule CLI do
  def main(_args) do
    # Try to enable raw mode on the IO device
    # This works if stdin is connected to a terminal
    try do
      # Get the group leader (IO server)
      group_leader = Process.group_leader()

      # Try to put the terminal in raw mode using Erlang's internal functions
      # This bypasses the need for external stty
      :io.setopts(group_leader, [binary: true, encoding: :latin1])

      # Try to set raw mode on standard_io
      case :io.setopts(:standard_io, binary: true, encoding: :latin1, echo: false) do
        :ok -> :ok
        _ -> :ok
      end
    catch
      _, _ -> :ok
    end

    IO.write("$ ")
    loop("", [], nil)
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
      # Handle both \n (cooked) and \r (raw) for Enter
      ch == ?\n or ch == ?\r ->
        # Only echo newline if we got \r (raw mode)
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
