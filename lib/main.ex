defmodule CLI do
  def main(_args) do
    # Configure IO options
    :io.setopts(:standard_io, binary: true, encoding: :latin1)

    # Try to disable echo (may not work in all environments)
    :io.setopts(:standard_io, echo: false)

    IO.write("$ ")
    loop("", [], nil)
  end

  defp loop(current, history, cursor) do
    # Check if current ends with ^[[ (Windows bash escape sequence start)
    if String.ends_with?(current, "^[[") do
      # Read next char to see if it's A (up arrow)
      case IO.getn("", 1) do
        "A" ->
          # Remove ^[[ from current and handle up arrow
          trimmed = String.slice(current, 0..-4//1)
          handle_up_arrow(trimmed, history, cursor)

        other ->
          loop(current <> other, history, cursor)
      end
    else
      case IO.getn("", 1) do
        "\n" ->
          cmd = String.trim(current)

          if cmd != "" do
            execute_command(cmd)
            IO.write("$ ")
            loop("", history ++ [cmd], nil)
          else
            IO.write("$ ")
            loop("", history, nil)
          end

        <<27>> ->
          handle_escape(current, history, cursor)

        <<c>> when c < 32 and c != ?\n ->
          loop(current, history, cursor)

        <<c>> ->
          loop(current <> <<c>>, history, nil)

        _ ->
          loop(current, history, cursor)
      end
    end
  end

  defp handle_escape(current, history, cursor) do
    # Read the next byte after ESC
    byte1 = IO.getn("", 1)

    case byte1 do
      "[" ->
        # Read the third byte
        byte2 = IO.getn("", 1)

        case byte2 do
          "A" ->
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
      new_cursor =
        case cursor do
          nil -> length(history) - 1
          0 -> 0
          n -> n - 1
        end

      recalled = Enum.at(history, new_cursor)

      if recalled do
        clear_len = String.length(current) + 2
        IO.write("\r" <> String.duplicate(" ", clear_len) <> "\r")
        IO.write("$ " <> recalled)
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
