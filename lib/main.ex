defmodule CLI do
  def main(_args) do
    # Configure IO for binary input
    :io.setopts(:standard_io, binary: true, encoding: :latin1)

    # Write prompt to stderr
    IO.write(:standard_error, "$ ")

    loop("", [], nil)
  end

  defp loop(current, history, cursor) do
    # Read one character at a time
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
      # Handle Enter - in raw mode it's \r, in cooked mode it's \n
      ch == ?\n or ch == ?\r ->
        # Echo newline (OPOST will convert \n to \r\n)
        IO.write(:standard_error, "\n")

        cmd = String.trim(current)

        if cmd != "" do
          # Add to history first, then execute
          new_history = history ++ [cmd]
          execute_command(cmd, new_history)
          IO.write(:standard_error, "$ ")
          loop("", new_history, nil)
        else
          IO.write(:standard_error, "$ ")
          loop("", history, nil)
        end

      # ESC byte - start of arrow key sequence
      ch == 27 ->
        handle_escape(current, history, cursor)

      # Other control characters - ignore
      ch < 32 ->
        loop(current, history, cursor)

      # Regular character
      true ->
        # Echo in raw mode so user sees what they type
        IO.write(:standard_error, <<ch>>)
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
      # Calculate new cursor position
      new_cursor =
        case cursor do
          nil -> length(history) - 1
          0 -> 0
          n -> n - 1
        end

      recalled = Enum.at(history, new_cursor)

      if recalled do
        # Clear current line if needed
        current_len = String.length(current)
        if current_len > 0 do
          for _ <- 1..current_len do
            IO.write(:standard_error, "\b \b")
          end
        end

        # Write recalled command
        IO.write(:standard_error, recalled)

        # Continue loop with recalled command
        loop(recalled, history, new_cursor)
      else
        loop(current, history, cursor)
      end
    end
  end

  defp execute_command("exit", _history), do: System.halt(0)

  defp execute_command("pwd", _history) do
    IO.puts(File.cwd!())
  end

  defp execute_command(cmd, history) do
    # Check if command contains pipes
    if String.contains?(cmd, "|") do
      execute_pipeline(cmd)
    else
      execute_single_command(cmd, history)
    end
  end

  defp execute_single_command(cmd, history) do
    case String.split(cmd) do
      ["type", command] ->
        execute_type(command)

      ["history"] ->
        # Show all history
        print_history(history, nil)

      ["history", n_str] ->
        # Show last N entries
        case Integer.parse(n_str) do
          {n, ""} -> print_history(history, n)
          _ -> IO.puts("history: #{n_str}: numeric argument required")
        end

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

  defp execute_pipeline(cmd) do
    # For pipelines, use the system shell to handle it via Port
    # This allows us to handle commands that don't terminate (like tail -f)
    port = Port.open({:spawn, "sh -c '#{String.replace(cmd, "'", "'\\''")}'"},
      [:binary, :exit_status])

    # Collect output - wait for pipeline to complete or timeout (10 seconds)
    output = collect_pipeline_output(port, "")

    IO.write(output)
    unless String.ends_with?(output, "\n") do
      IO.write("\n")
    end
  end

  defp collect_pipeline_output(port, acc, retries \\ 0) do
    receive do
      {^port, {:data, data}} ->
        # Got data, keep collecting with retries reset
        collect_pipeline_output(port, acc <> data, 0)
      {^port, {:exit_status, _}} ->
        # Process exited, flush any remaining data and return
        flush_pipeline_data(port, acc)
    after
      100 ->
        # No data for 100ms
        if retries < 100 do
          # Keep waiting - up to 10 seconds total (100 * 100ms)
          collect_pipeline_output(port, acc, retries + 1)
        else
          # Timeout after 10 seconds - kill port and return what we have
          Port.close(port)
          flush_pipeline_data(port, acc)
        end
    end
  end

  defp flush_pipeline_data(port, acc) do
    receive do
      {^port, {:data, data}} ->
        flush_pipeline_data(port, acc <> data)
    after
      0 -> acc
    end
  end

  defp print_history(history, limit) do
    entries = if limit, do: Enum.take(history, -limit), else: history
    start_index = length(history) - length(entries) + 1

    entries
    |> Enum.with_index(start_index)
    |> Enum.each(fn {cmd, idx} ->
      IO.puts("#{String.pad_leading(Integer.to_string(idx), 5)}  #{cmd}")
    end)
  end

  defp execute_type(command) do
    builtins = ["exit", "echo", "type", "pwd", "cd", "history"]

    cond do
      command in builtins ->
        IO.puts("#{command} is a shell builtin")

      path = System.find_executable(command) ->
        IO.puts("#{command} is #{path}")

      true ->
        IO.puts("#{command}: not found")
    end
  end
end
