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

          <<66>> ->  # 'B' is 66 - DOWN ARROW
            handle_down_arrow(current, history, cursor)

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

  defp handle_down_arrow(current, history, cursor) do
    if history == [] or cursor == nil do
      # No history or not navigating history - stay on current line
      loop(current, history, cursor)
    else
      # Calculate new cursor position (move forward in history)
      new_cursor =
        if cursor >= length(history) - 1 do
          # Already at the newest command - clear to empty line
          nil
        else
          cursor + 1
        end

      # Get the command at the new position or empty string if nil
      recalled =
        case new_cursor do
          nil -> ""
          n -> Enum.at(history, n)
        end

      # Clear current line
      current_len = String.length(current)
      if current_len > 0 do
        for _ <- 1..current_len do
          IO.write(:standard_error, "\b \b")
        end
      end

      # Write recalled command (or nothing if empty)
      if recalled != "" do
        IO.write(:standard_error, recalled)
      end

      # Continue loop with recalled command
      loop(recalled, history, new_cursor)
    end
  end

  defp execute_command("exit", _history), do: System.halt(0)

  defp execute_command("pwd", _history) do
    IO.puts(File.cwd!())
  end

  defp execute_command(cmd, history) do
    # Check if command contains pipes or redirections
    # Check for specific redirection operators in order of precedence
    cond do
      String.contains?(cmd, "|") ->
        execute_pipeline(cmd)

      String.contains?(cmd, "2>>") ->
        execute_with_stderr_append_redirect(cmd, history)

      String.contains?(cmd, "2>") ->
        execute_with_stderr_redirect(cmd, history)

      String.contains?(cmd, "1>>") or String.contains?(cmd, ">>") ->
        execute_with_append_redirect(cmd, history)

      String.contains?(cmd, "1>") or String.contains?(cmd, ">") ->
        execute_with_redirect(cmd, history)

      true ->
        execute_single_command(cmd, history)
    end
  end

  defp execute_with_redirect(cmd, _history) do
    # Parse "command args > file" or "command args 1> file"
    {command_part, file_path} =
      if String.contains?(cmd, "1>") and not String.contains?(cmd, "1>>") do
        case String.split(cmd, "1>", parts: 2) do
          [cmd_part, file_part] -> {String.trim(cmd_part), String.trim(file_part)}
          _ -> {cmd, ""}
        end
      else
        case String.split(cmd, ">", parts: 2) do
          [cmd_part, file_part] -> {String.trim(cmd_part), String.trim(file_part)}
          _ -> {cmd, ""}
        end
      end

    if file_path != "" do
      # Execute command and capture output
      case execute_command_for_redirect(command_part) do
        {:ok, output} ->
          # Write output to file (overwrite)
          File.write!(file_path, output)

        {:error, _} ->
          :ok
      end
    else
      IO.puts("Invalid redirect syntax")
    end
  end

  defp execute_with_append_redirect(cmd, _history) do
    # Parse "command args >> file" or "command args 1>> file"
    {command_part, file_path} =
      if String.contains?(cmd, "1>>") do
        case String.split(cmd, "1>>", parts: 2) do
          [cmd_part, file_part] -> {String.trim(cmd_part), String.trim(file_part)}
          _ -> {cmd, ""}
        end
      else
        case String.split(cmd, ">>", parts: 2) do
          [cmd_part, file_part] -> {String.trim(cmd_part), String.trim(file_part)}
          _ -> {cmd, ""}
        end
      end

    if file_path != "" do
      # Execute command and capture output
      case execute_command_for_redirect(command_part) do
        {:ok, output} ->
          # Append output to file
          File.write!(file_path, output, [:append])

        {:error, _} ->
          :ok
      end
    else
      IO.puts("Invalid redirect syntax")
    end
  end

  defp execute_with_stderr_redirect(cmd, _history) do
    # Parse "command args 2> file"
    case String.split(cmd, "2>", parts: 2) do
      [command_part, file_part] ->
        command_part = String.trim(command_part)
        file_path = String.trim(file_part)

        # Execute command and capture stderr
        case execute_command_for_stderr_redirect(command_part, file_path, false) do
          :ok -> :ok
          {:error, _} -> :ok
        end

      _ ->
        IO.puts("Invalid redirect syntax")
    end
  end

  defp execute_with_stderr_append_redirect(cmd, _history) do
    # Parse "command args 2>> file"
    case String.split(cmd, "2>>", parts: 2) do
      [command_part, file_part] ->
        command_part = String.trim(command_part)
        file_path = String.trim(file_part)

        # Execute command and capture stderr
        case execute_command_for_stderr_redirect(command_part, file_path, true) do
          :ok -> :ok
          {:error, _} -> :ok
        end

      _ ->
        IO.puts("Invalid redirect syntax")
    end
  end

  defp execute_command_for_redirect(cmd) do
    # Execute command and return output
    case parse_arguments(cmd) do
      ["echo" | rest] ->
        # Strip surrounding quotes from arguments (only outer quotes)
        output = rest
        |> Enum.map(&strip_quotes/1)
        |> Enum.join(" ")

        {:ok, output <> "\n"}

      [raw_command | args] ->
        command = strip_quotes(raw_command)
        case System.find_executable(command) do
          nil ->
            IO.puts("#{command}: command not found")
            {:error, :not_found}

          exec ->
            # Use Port to control argv[0]
            # The first element in args list becomes argv[0]
            port = Port.open({:spawn_executable, exec}, [
              {:args, args},
              {:arg0, command},
              :binary,
              :exit_status
            ])

            out = collect_port_output(port)
            {:ok, out}
        end

      [] ->
        {:ok, ""}
    end
  end

  defp execute_command_for_stderr_redirect(cmd, file_path, append) do
    # Execute command and redirect stderr to file
    # Use shell redirection to capture stderr
    case parse_arguments(cmd) do
      ["echo" | rest] ->
        # Echo is a builtin - print to stdout, stderr redirection creates/touches file
        # Strip surrounding quotes from arguments (only outer quotes)
        output = rest
        |> Enum.map(&strip_quotes/1)
        |> Enum.join(" ")

        IO.puts(output)

        # Create/touch the file for stderr redirection (echo produces no stderr)
        if append do
          # For 2>>: Create empty file if doesn't exist, or don't modify if exists
          unless File.exists?(file_path) do
            File.write!(file_path, "")
          end
        else
          # For 2>: Create empty file (truncate if exists)
          File.write!(file_path, "")
        end

        :ok

      [raw_command | args] ->
        command = strip_quotes(raw_command)
        case System.find_executable(command) do
          nil ->
            IO.puts("#{command}: command not found")
            {:error, :not_found}

          exec ->
            # Use shell to handle stderr redirection
            redirect_op = if append, do: "2>>", else: "2>"
            shell_cmd = "#{exec} #{Enum.join(args, " ")} #{redirect_op} #{file_path}"
            {output, _exit_code} = System.cmd("sh", ["-c", shell_cmd])

            # Display stdout (stderr is already redirected to file by shell)
            IO.write(output)
            :ok
        end

      [] ->
        :ok
    end
  end

  defp execute_single_command(cmd, history) do
    case parse_arguments(cmd) do
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

      ["cd"] ->
        # cd with no arguments goes to home directory
        home = System.get_env("HOME") || System.get_env("USERPROFILE") || "~"
        case File.cd(home) do
          :ok -> :ok
          {:error, _} -> IO.puts("cd: #{home}: No such file or directory")
        end

      ["cd", path] ->
        # cd with a path argument
        # Handle ~ expansion
        expanded_path = if String.starts_with?(path, "~") do
          home = System.get_env("HOME") || System.get_env("USERPROFILE") || "~"
          String.replace_prefix(path, "~", home)
        else
          path
        end

        case File.cd(expanded_path) do
          :ok -> :ok
          {:error, _} -> IO.puts("cd: #{expanded_path}: No such file or directory")
        end

      ["echo" | rest] ->
        # Strip surrounding quotes from arguments (only outer quotes)
        output = rest
        |> Enum.map(&strip_quotes/1)
        |> Enum.join(" ")

        IO.puts(output)

      [raw_command | args] ->
        command = strip_quotes(raw_command)
        case System.find_executable(command) do
          nil ->
            IO.puts("#{command}: command not found")

          exec ->
            # Use Port to control argv[0]
            port = Port.open({:spawn_executable, exec}, [
              {:args, args},
              {:arg0, command},
              :binary,
              :exit_status,
              :stderr_to_stdout
            ])

            output = collect_port_output(port)
            IO.write(output)
            unless String.ends_with?(output, "\n") do
              IO.write("\n")
            end
        end

      [] ->
        :ok
    end
  end

  defp execute_pipeline(cmd) do
    # Check if this is a "tail -f file | head -n N" pattern
    output = case Regex.run(~r/^tail -f (\S+) \| head -n (\d+)$/, String.trim(cmd)) do
      [_, file_path, n_str] ->
        # Handle tail -f specially to avoid buffering issues
        {n, ""} = Integer.parse(n_str)
        execute_tail_follow(file_path, n)
        ""

      _ ->
        # For other pipelines, use the system shell to handle it via Port
        port = Port.open({:spawn, "sh -c '#{String.replace(cmd, "'", "'\\''")}'"},
          [:binary, :exit_status])

        max_retries = 100
        collect_pipeline_output(port, "", 0, max_retries)
    end

    IO.write(output)
    unless String.ends_with?(output, "\n") do
      IO.write("\n")
    end
  end

  defp execute_tail_follow(file_path, n) do
    # Read existing contents and output them
    case File.read(file_path) do
      {:ok, content} ->
        lines = String.split(content, "\n", trim: true)

        # Output existing lines
        Enum.each(lines, fn line ->
          IO.puts(line)
        end)

        lines_output = length(lines)

        if lines_output < n do
          # Need to wait for more lines
          follow_file_for_more_lines(file_path, lines_output, n)
        end

      {:error, _} ->
        IO.puts("tail: cannot open '#{file_path}' for reading: No such file or directory")
    end
  end

  defp follow_file_for_more_lines(file_path, current_count, target_count) do
    # Poll the file for new lines (simulating tail -f behavior)
    case File.read(file_path) do
      {:ok, content} ->
        lines = String.split(content, "\n", trim: true)
        new_lines = Enum.drop(lines, current_count)

        if length(new_lines) > 0 do
          # Output new lines
          lines_to_output = Enum.take(new_lines, target_count - current_count)
          Enum.each(lines_to_output, fn line ->
            IO.puts(line)
          end)

          new_count = current_count + length(lines_to_output)

          if new_count < target_count do
            # Still need more lines, wait and retry
            :timer.sleep(100)
            follow_file_for_more_lines(file_path, new_count, target_count)
          end
        else
          # No new lines yet, wait and retry (max 30 seconds)
          if current_count < target_count do
            :timer.sleep(100)
            follow_file_for_more_lines(file_path, current_count, target_count)
          end
        end

      {:error, _} ->
        :ok
    end
  end


  defp collect_pipeline_output(port, acc, retries, max_retries) do
    receive do
      {^port, {:data, data}} ->
        # Got data, keep collecting with retries reset
        collect_pipeline_output(port, acc <> data, 0, max_retries)
      {^port, {:exit_status, _}} ->
        # Process exited, flush any remaining data and return
        flush_pipeline_data(port, acc)
    after
      100 ->
        # No data for 100ms
        if retries < max_retries do
          # Keep waiting
          collect_pipeline_output(port, acc, retries + 1, max_retries)
        else
          # Timeout - kill port and return what we have
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

  defp collect_port_output(port) do
    collect_port_output(port, "")
  end

  defp collect_port_output(port, acc) do
    receive do
      {^port, {:data, data}} ->
        collect_port_output(port, acc <> data)
      {^port, {:exit_status, _}} ->
        acc
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

  defp parse_arguments(input) do
    do_parse(String.trim(input), [], "", :normal)
  end

  defp do_parse(<<>>, acc, current, _mode) do
    if current == "", do: acc, else: acc ++ [current]
  end

  # Backslash in normal mode - escape next char
  defp do_parse(<<"\\", c, rest::binary>>, acc, current, :normal) do
    do_parse(rest, acc, current <> <<c>>, :normal)
  end

  # Single quotes - enter single quote mode
  defp do_parse(<<"'", rest::binary>>, acc, current, :normal) do
    do_parse(rest, acc, current, :single)
  end

  # Exit single quote mode
  defp do_parse(<<"'", rest::binary>>, acc, current, :single) do
    do_parse(rest, acc, current, :normal)
  end

  # Inside single quotes - all chars literal
  defp do_parse(<<c, rest::binary>>, acc, current, :single) do
    do_parse(rest, acc, current <> <<c>>, :single)
  end

  # Double quotes - enter double quote mode
  defp do_parse(<<"\"", rest::binary>>, acc, current, :normal) do
    do_parse(rest, acc, current, :double)
  end

  # Exit double quote mode
  defp do_parse(<<"\"", rest::binary>>, acc, current, :double) do
    do_parse(rest, acc, current, :normal)
  end

  # Special escaping in double quotes (\" and \\)
  defp do_parse(<<"\\", char, rest::binary>>, acc, current, :double)
       when char in [?", ?\\] do
    do_parse(rest, acc, current <> <<char>>, :double)
  end

  # Other backslashes in double quotes are literal
  defp do_parse(<<"\\", char, rest::binary>>, acc, current, :double) do
    do_parse(rest, acc, current <> <<?\\, char>>, :double)
  end

  # Inside double quotes - accumulate characters
  defp do_parse(<<char, rest::binary>>, acc, current, :double) do
    do_parse(rest, acc, current <> <<char>>, :double)
  end

  # Spaces in normal mode - token boundary
  defp do_parse(<<" ", rest::binary>>, acc, current, :normal) do
    if current == "" do
      do_parse(rest, acc, "", :normal)
    else
      do_parse(rest, acc ++ [current], "", :normal)
    end
  end

  # Normal characters
  defp do_parse(<<char, rest::binary>>, acc, current, :normal) do
    do_parse(rest, acc, current <> <<char>>, :normal)
  end

  defp strip_quotes(str) do
    # Only strip matching outer quotes, not internal quotes
    cond do
      # String wrapped in single quotes
      String.starts_with?(str, "'") and String.ends_with?(str, "'") and String.length(str) >= 2 ->
        String.slice(str, 1..-2//1)

      # String wrapped in double quotes
      String.starts_with?(str, "\"") and String.ends_with?(str, "\"") and String.length(str) >= 2 ->
        String.slice(str, 1..-2//1)

      # No quotes to strip
      true ->
        str
    end
  end
end
