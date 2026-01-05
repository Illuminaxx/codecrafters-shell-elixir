defmodule CLI do
  import Bitwise

  def main(_args) do
    :io.setopts(:standard_io, binary: true, encoding: :latin1, echo: false)
    IO.write("$ ")
    loop("", [])
  end

  defp loop(current, history) do
    case IO.getn("", 1) do
      "\n" ->
        cmd = String.trim(current)

        if cmd != "" do
          handle_command(cmd, history)
          IO.write("$ ")
          loop("", history ++ [cmd])
        else
          IO.write("$ ")
          loop("", history)
        end

      <<c>> ->
        loop(current <> <<c>>, history)

      _ ->
        loop(current, history)
    end
  end

  defp handle_command("history", history) do
    Enum.with_index(history, 1)
    |> Enum.each(fn {cmd, i} ->
      IO.puts("  #{i}  #{cmd}")
    end)
  end

  defp handle_command(cmd, history) do
    if has_redirection?(cmd) or String.contains?(cmd, "|") do
      handle_via_sh(cmd)
    else
      cond do
        cmd == "cd" -> handle_cd("~")
        String.starts_with?(cmd, "cd ") -> handle_cd(String.trim_leading(cmd, "cd "))
        String.starts_with?(cmd, "echo") -> handle_echo(cmd)
        String.starts_with?(cmd, "type ") -> handle_type(cmd)
        cmd == "pwd" -> IO.puts(File.cwd!())
        cmd == "exit" -> System.halt(0)
        true -> handle_external(cmd)
      end
    end
  end

  defp has_redirection?(cmd) do
    String.contains?(cmd, ["2>", "1>", ">>", ">"])
  end

  defp handle_cd(path) do
    resolved =
      cond do
        path == "~" -> System.get_env("HOME")
        String.starts_with?(path, "~/") -> String.replace_prefix(path, "~", System.get_env("HOME"))
        true -> path
      end

    case File.cd(resolved) do
      :ok -> :ok
      {:error, _} -> IO.puts("cd: #{path}: No such file or directory")
    end
  end

  defp handle_echo(cmd) do
    args =
      cmd
      |> String.replace_prefix("echo", "")
      |> parse_arguments()

    IO.puts(Enum.join(args, " "))
  end

  defp handle_type(cmd) do
    arg = String.trim_leading(cmd, "type ") |> String.trim()
    builtins = ["echo", "cd", "pwd", "type", "exit", "history"]

    cond do
      arg in builtins -> IO.puts("#{arg} is a shell builtin")
      exec = find_executable(arg) -> IO.puts("#{arg} is #{exec}")
      true -> IO.puts("#{arg}: not found")
    end
  end

  defp handle_external(cmd) do
    case parse_arguments(cmd) do
      [] -> :ok
      [command | args] ->
        case find_executable(command) do
          nil ->
            IO.puts("#{command}: command not found")

          exec_path ->
            port =
              Port.open(
                {:spawn_executable, exec_path},
                [:binary, :exit_status, {:args, args}, {:arg0, command}, {:line, 4096}]
              )

            receive_output(port)
        end
    end
  end

  defp handle_via_sh(cmd) do
    port =
      Port.open(
        {:spawn, ~c"sh -c '#{escape_single_quotes(cmd)}'"},
        [:binary, :exit_status, {:line, 4096}]
      )

    receive_output(port)
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

  defp escape_single_quotes(str),
    do: String.replace(str, "'", "'\\''")

  defp parse_arguments(input),
    do: do_parse(String.trim(input), [], "", :normal)

  defp do_parse(<<>>, acc, current, _),
    do: if(current == "", do: acc, else: acc ++ [current])

  defp do_parse(<<"\\", c, rest::binary>>, acc, cur, :normal),
    do: do_parse(rest, acc, cur <> <<c>>, :normal)

  defp do_parse(<<"'", rest::binary>>, acc, cur, :normal),
    do: do_parse(rest, acc, cur, :single)

  defp do_parse(<<"'", rest::binary>>, acc, cur, :single),
    do: do_parse(rest, acc, cur, :normal)

  defp do_parse(<<c, rest::binary>>, acc, cur, :single),
    do: do_parse(rest, acc, cur <> <<c>>, :single)

  defp do_parse(<<"\"", rest::binary>>, acc, cur, :normal),
    do: do_parse(rest, acc, cur, :double)

  defp do_parse(<<"\"", rest::binary>>, acc, cur, :double),
    do: do_parse(rest, acc, cur, :normal)

  defp do_parse(<<"\\", c, rest::binary>>, acc, cur, :double)
       when c in [?\", ?\\],
    do: do_parse(rest, acc, cur <> <<c>>, :double)

  defp do_parse(<<"\\", c, rest::binary>>, acc, cur, :double),
    do: do_parse(rest, acc, cur <> <<?\\, c>>, :double)

  defp do_parse(<<c, rest::binary>>, acc, cur, :double),
    do: do_parse(rest, acc, cur <> <<c>>, :double)

  defp do_parse(<<" ", rest::binary>>, acc, cur, :normal) do
    if cur == "" do
      do_parse(rest, acc, "", :normal)
    else
      do_parse(rest, acc ++ [cur], "", :normal)
    end
  end

  defp do_parse(<<c, rest::binary>>, acc, cur, :normal),
    do: do_parse(rest, acc, cur <> <<c>>, :normal)
end
