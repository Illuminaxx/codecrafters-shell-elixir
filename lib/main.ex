defmodule CLI do
  import Bitwise

  def main(_args) do
    :io.setopts(:standard_io, binary: true, encoding: :latin1, echo: false)
    IO.write("$ ")
    loop("")
  end

  defp loop(current) do
    case IO.getn("", 1) do
      "\n" ->
        cmd = String.trim(current)
        if cmd != "", do: handle_command(cmd)
        IO.write("$ ")
        loop("")

      <<c>> ->
        loop(current <> <<c>>)

      _ ->
        loop(current)
    end
  end

  # =========================
  # COMMAND DISPATCH
  # =========================
defp handle_command("exit"), do: System.halt(0)
  defp handle_command("pwd"), do: IO.puts(File.cwd!())

  defp handle_command(cmd) do
    cond do
      cmd == "cd" -> handle_cd("~")
      String.starts_with?(cmd, "cd ") -> handle_cd(String.trim_leading(cmd, "cd "))
      String.starts_with?(cmd, "echo") -> handle_echo(cmd)
      String.starts_with?(cmd, "type ") -> handle_type(cmd)
      true -> handle_external(cmd)
    end
  end

  # =========================
  # BUILTINS
  # =========================
  defp handle_cd(path) do
    resolved =
      cond do
        path == "~" ->
          System.get_env("HOME")

        String.starts_with?(path, "~/") ->
          String.replace_prefix(path, "~", System.get_env("HOME"))

        true ->
          path
      end

    case File.cd(resolved) do
      :ok -> :ok
      {:error, _} -> IO.puts("cd: #{path}: No such file or directory")
    end
  end

  defp handle_echo(cmd) do
    {raw_args, outfile} =
      cmd
      |> String.replace_prefix("echo", "")
      |> parse_with_redirection()

    # 👈 AJOUT
    args = parse_arguments(raw_args)

    write_output(Enum.join(args, " "), outfile)
  end

  defp handle_type(cmd) do
    arg = String.trim_leading(cmd, "type ") |> String.trim()

    builtins = ["echo", "cd", "pwd", "type", "exit"]

    cond do
      arg in builtins -> IO.puts("#{arg} is a shell builtin")
      exec = find_executable(arg) -> IO.puts("#{arg} is #{exec}")
      true -> IO.puts("#{arg}: not found")

    end
  end

  # =========================
  # EXTERNAL COMMANDS
  # =========================
  defp handle_external(cmd) do
    {cmd_part, outfile} = parse_with_redirection(cmd)
    parts = parse_arguments(cmd_part)

    case parts do
      [] ->
        :ok

      [exe | args] ->
        case find_executable(exe) do
          nil ->
            IO.puts("#{exe}: command not found")

          path ->
            port =
              Port.open(
                {:spawn_executable, to_charlist(path)},
                [
                  {:arg0, to_charlist(exe)},
                  {:args, Enum.map(args, &to_charlist/1)},
                  :binary,
                  :exit_status
                ]
              )

            collect_output(port, outfile, "")
        end
    end
  end

  defp collect_output(port, outfile, acc) do
    receive do
      {^port, {:data, data}} ->
        collect_output(port, outfile, acc <> data)

      {^port, {:exit_status, _}} ->
        write_output(String.trim_trailing(acc), outfile)
    end
  end

  # =========================
  # REDIRECTION
  # =========================
  defp parse_with_redirection(cmd) do
    case Regex.run(~r/(.*?)(?:\s+1?>\s*|\s+>\s*)(\S+)/, cmd) do
      [_, left, file] -> {left, file}
      _ -> {cmd, nil}
    end
  end

  defp write_output(text, nil), do: IO.puts(text)
  defp write_output(text, file), do: File.write!(file, text <> "\n")

  # =========================
  # EXECUTABLE LOOKUP
  # =========================
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

  # =========================
  # ARGUMENT PARSER
  # =========================
  defp parse_arguments(input), do: do_parse(String.trim(input), [], "", :normal)

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

  defp do_parse(<<"\\", c, rest::binary>>, acc, cur, :double) when c in [?\", ?\\],
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
