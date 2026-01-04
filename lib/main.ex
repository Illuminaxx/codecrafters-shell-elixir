defmodule CLI do
  import Bitwise

  @builtins ["echo", "exit", "type", "pwd", "cd", "history"]

  def main(_args) do
    :io.setopts(:standard_io, [
      binary: true,
      encoding: :latin1,
      echo: false
    ])

    IO.write("$ ")
    loop("", [], 0, :normal, false)
  end

  defp loop(current, history, hist_index, :normal, from_history) do
    case IO.getn("", 1) do
      "\e" -> loop(current, history, hist_index, :esc, from_history)

      "\n" ->
        cmd = String.trim(current)
        new_history = if cmd == "", do: history, else: history ++ [cmd]
        unless cmd == "", do: handle_command(cmd, new_history)

        if cmd != "exit" do
          IO.write("$ ")
          loop("", new_history, 0, :normal, false)
        end

      <<char>> ->
        loop(current <> <<char>>, history, hist_index, :normal, false)

      _ ->
        loop(current, history, hist_index, :normal, from_history)
    end
  end

  defp loop(current, history, hist_index, :esc, from_history) do
    case IO.getn("", 1) do
      "[" -> loop(current, history, hist_index, :bracket, from_history)
      _ -> loop(current, history, hist_index, :normal, from_history)
    end
  end

  defp loop(current, history, hist_index, :bracket, from_history) do
    case IO.getn("", 1) do
      "A" -> recall_up(history, hist_index)
      "B" -> recall_down(history, hist_index)
      _ -> loop(current, history, hist_index, :normal, from_history)
    end
  end

  defp recall_up(history, hist_index) do
    max = length(history)
    new_index = min(hist_index + 1, max)

    recalled =
      if new_index == 0 do
        ""
      else
        Enum.at(history, max - new_index) || ""
      end

    IO.write("\r\e[2K$ ")
    IO.write(recalled)
    loop(recalled, history, new_index, :normal, true)
  end

  defp recall_down(history, hist_index) do
    new_index = max(hist_index - 1, 0)

    recalled =
      if new_index == 0 do
        ""
      else
        Enum.at(history, length(history) - new_index) || ""
      end

    IO.write("\r\e[2K$ ")
    IO.write(recalled)
    loop(recalled, history, new_index, :normal, true)
  end

  defp handle_command("", _), do: :ok

  defp handle_command(cmd, history) do
    cond do
      String.contains?(cmd, "|") -> handle_pipeline(cmd)
      cmd == "exit" -> :ok
      cmd == "history" -> handle_history(history, nil)

      String.starts_with?(cmd, "history ") ->
        case Integer.parse(String.trim_leading(cmd, "history ")) do
          {n, ""} -> handle_history(history, n)
          _ -> handle_history(history, nil)
        end

      String.starts_with?(cmd, "echo ") -> handle_echo_command(cmd)
      cmd == "echo" -> IO.puts("")
      cmd == "pwd" -> IO.puts(File.cwd!())
      String.starts_with?(cmd, "cd ") -> handle_cd_command(cmd)
      String.starts_with?(cmd, "type ") -> handle_type_command(cmd)
      true -> handle_external_command(cmd)
    end
  end

  defp handle_history(history, nil) do
    history
    |> Enum.with_index(1)
    |> Enum.each(fn {cmd, idx} ->
      IO.puts("    #{idx}  #{cmd}")
    end)
  end

  defp handle_history(history, n) when is_integer(n) and n > 0 do
    history
    |> Enum.take(-n)
    |> Enum.with_index(length(history) - n + 1)
    |> Enum.each(fn {cmd, idx} ->
      IO.puts("    #{idx}  #{cmd}")
    end)
  end

  defp handle_echo_command(cmd) do
    input = String.replace_prefix(cmd, "echo ", "")
    args = parse_arguments(input)
    IO.puts(Enum.join(args, " "))
  end

  defp handle_cd_command(cmd) do
    path = String.replace_prefix(cmd, "cd ", "") |> String.trim()

    resolved =
      cond do
        path == "~" -> System.get_env("HOME") || "~"
        String.starts_with?(path, "~/") ->
          String.replace_prefix(path, "~", System.get_env("HOME") || "~")
        true -> path
      end

    case File.cd(resolved) do
      :ok -> :ok
      {:error, _} -> IO.puts("cd: #{path}: No such file or directory")
    end
  end

  defp handle_type_command(cmd) do
    arg = String.replace_prefix(cmd, "type ", "")

    cond do
      arg in @builtins -> IO.puts("#{arg} is a shell builtin")
      exec = find_executable(arg) -> IO.puts("#{arg} is #{exec}")
      true -> IO.puts("#{arg}: not found")
    end
  end

  defp handle_pipeline(cmd) do
    port =
      Port.open(
        {:spawn, ~c"sh -c '#{escape_single_quotes(cmd)}'"},
        [:binary, :exit_status, {:line, 4096}]
      )

    receive_output(port)
  end

  defp handle_external_command(cmd) do
    parts = parse_arguments(cmd)

    case parts do
      [] -> :ok
      [cmd | args] ->
        case find_executable(cmd) do
          nil -> IO.puts("#{cmd}: command not found")

          exec ->
            port =
              :erlang.open_port(
                {:spawn_executable, to_charlist(exec)},
                [
                  {:arg0, to_charlist(cmd)},
                  {:args, Enum.map(args, &to_charlist/1)},
                  :binary,
                  :exit_status,
                  {:line, 1024}
                ]
              )

            receive_output(port)
        end
    end
  end

  defp receive_output(port) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        IO.puts(line)
        receive_output(port)

      {^port, {:data, {:noeol, data}}} ->
        IO.write(data)
        receive_output(port)

      {^port, {:exit_status, _}} ->
        :ok
    end
  end

  defp escape_single_quotes(str), do: String.replace(str, "'", "'\\''")

  defp find_executable(cmd) do
    System.get_env("PATH", "")
    |> String.split(":")
    |> Enum.find_value(fn dir ->
      path = Path.join(dir, cmd)

      if File.exists?(path) do
        case File.stat(path) do
          {:ok, %File.Stat{mode: mode}} when (mode &&& 0o111) != 0 -> path
          _ -> nil
        end
      end
    end)
  end

  # ============================
  # ARGUMENT PARSER
  # Supports:
  # - single quotes
  # - double quotes
  # - backslash outside quotes
  # ============================
  defp parse_arguments(input) do
    do_parse(String.trim(input), [], "", :normal)
  end

  defp do_parse(<<>>, acc, current, _mode) do
    if current == "", do: acc, else: acc ++ [current]
  end

  # Backslash (ONLY in normal mode)
  defp do_parse(<<"\\" , c, rest::binary>>, acc, current, :normal) do
    do_parse(rest, acc, current <> <<c>>, :normal)
  end

  # Single quotes
  defp do_parse(<<"'", rest::binary>>, acc, current, :normal),
    do: do_parse(rest, acc, current, :single)

  defp do_parse(<<"'", rest::binary>>, acc, current, :single),
    do: do_parse(rest, acc, current, :normal)

  defp do_parse(<<c, rest::binary>>, acc, current, :single),
    do: do_parse(rest, acc, current <> <<c>>, :single)

  # Double quotes
  defp do_parse(<<"\"", rest::binary>>, acc, current, :normal),
    do: do_parse(rest, acc, current, :double)

  defp do_parse(<<"\"", rest::binary>>, acc, current, :double),
    do: do_parse(rest, acc, current, :normal)

  defp do_parse(<<c, rest::binary>>, acc, current, :double),
    do: do_parse(rest, acc, current <> <<c>>, :double)

  # Spaces
  defp do_parse(<<" ", rest::binary>>, acc, current, :normal) do
    if current == "" do
      do_parse(rest, acc, "", :normal)
    else
      do_parse(rest, acc ++ [current], "", :normal)
    end
  end

  # Normal characters
  defp do_parse(<<c, rest::binary>>, acc, current, :normal),
    do: do_parse(rest, acc, current <> <<c>>, :normal)
end
