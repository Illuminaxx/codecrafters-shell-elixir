defmodule CLI do
  import Bitwise

  @builtins ["echo", "exit", "type", "pwd", "cd"]

  def main(_args) do
    loop()
  end

  defp loop do
    # Afficher seulement le prompt initial
    IO.write("$ ")

    case read_line("") do
      :eof -> :ok
      line ->
        cmd = String.trim(line)
        handle_command(cmd)
        if cmd != "exit", do: loop()
    end
  end

  defp read_line(buffer) do
    case :file.read(:standard_io, 1) do
      {:ok, "\n"} ->
        IO.write("\n")
        buffer

      {:ok, "\t"} ->
        # TAB : compléter et afficher le résultat
        new_buffer = complete(buffer)
        if new_buffer != buffer do
          # Afficher seulement la partie ajoutée
          added = String.slice(new_buffer, String.length(buffer)..-1//1)
          IO.write(added)
        end
        read_line(new_buffer)

      {:ok, <<127>>} ->
        # Backspace
        if buffer != "" do
          IO.write("\b \b")
          read_line(String.slice(buffer, 0..-2//1))
        else
          read_line(buffer)
        end

      {:ok, char} ->
        IO.write(char)
        read_line(buffer <> char)

      :eof ->
        :eof

      {:error, _} ->
        :eof
    end
  end

  defp complete(buffer) do
    if not String.contains?(buffer, " ") and buffer != "" do
      matches = Enum.filter(@builtins, &String.starts_with?(&1, buffer))

      case matches do
        [single] -> single <> " "
        _ -> buffer
      end
    else
      buffer
    end
  end

  defp handle_command(""), do: :ok

  defp handle_command(cmd) do
    cond do
      cmd === "exit" ->
        :ok

      String.starts_with?(cmd, "echo ") ->
        handle_echo_command(cmd)

      cmd === "echo" ->
        handle_echo_empty(cmd)

      cmd === "pwd" ->
        IO.puts(File.cwd!())

      String.starts_with?(cmd, "cd ") ->
        handle_cd_command(cmd)

      String.starts_with?(cmd, "type ") ->
        handle_type_command(cmd)

      true ->
        handle_external_command(cmd)
    end
  end

  defp handle_echo_command(cmd) do
    if String.contains?(cmd, ">") do
      execute_via_shell(cmd)
    else
      input = String.replace_prefix(cmd, "echo ", "")
      args = parse_arguments(input)
      output = Enum.join(args, " ")
      IO.puts(output)
    end
  end

  defp handle_echo_empty(cmd) do
    if String.contains?(cmd, ">") do
      execute_via_shell(cmd)
    else
      IO.puts("")
    end
  end

  defp handle_cd_command(cmd) do
    path = String.replace_prefix(cmd, "cd ", "")

    expanded_path =
      cond do
        path === "~" ->
          System.get_env("HOME") || "~"

        String.starts_with?(path, "~/") ->
          home = System.get_env("HOME") || "~"
          String.replace_prefix(path, "~", home)

        true ->
          path
      end

    case File.cd(expanded_path) do
      :ok -> :ok
      {:error, _reason} -> IO.puts("cd: #{path}: No such file or directory")
    end
  end

  defp handle_type_command(cmd) do
    arg = String.replace_prefix(cmd, "type ", "")
    builtin? = arg in @builtins

    cond do
      builtin? -> IO.puts("#{arg} is a shell builtin")
      exec = find_executable(arg) -> IO.puts("#{arg} is #{exec}")
      true -> IO.puts("#{arg}: not found")
    end
  end

  defp handle_external_command(cmd) do
    if String.contains?(cmd, ">") do
      execute_via_shell(cmd)
    else
      execute_direct(cmd)
    end
  end

  defp execute_via_shell(cmd) do
    port = :erlang.open_port(
      {:spawn, to_charlist("sh -c " <> shell_quote(cmd))},
      [:binary, :exit_status, {:line, 1024}]
    )
    receive_output(port)
  end

  defp execute_direct(cmd) do
    parts = parse_arguments(cmd)

    if parts == [] do
      :ok
    else
      command_name = hd(parts)

      case find_executable(command_name) do
        nil ->
          IO.puts("#{cmd}: command not found")

        exec ->
          args = tl(parts)
          port_opts = [
            {:arg0, to_charlist(command_name)},
            {:args, Enum.map(args, &to_charlist/1)},
            :binary, :exit_status, {:line, 1024}
          ]
          port = :erlang.open_port({:spawn_executable, to_charlist(exec)}, port_opts)
          receive_output(port)
      end
    end
  end

  defp receive_output(port) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        IO.puts(line)
        receive_output(port)
      {^port, {:exit_status, _status}} ->
        :ok
    end
  end

  defp shell_quote(cmd) do
    "'" <> String.replace(cmd, "'", "'\\''") <> "'"
  end

  defp find_executable(cmd) do
    path = System.get_env("PATH") || ""
    dirs = String.split(path, ":")

    Enum.find_value(dirs, fn dir ->
      candidate = Path.join(dir, cmd)
      if File.exists?(candidate) do
        case File.stat(candidate) do
          {:ok, %File.Stat{mode: mode}} ->
            if (mode &&& 0o111) != 0, do: candidate, else: false
          _ -> false
        end
      else
        false
      end
    end)
  end

  defp parse_arguments(input), do: parse_args(input, "", [], :none)

  defp parse_args("", current, acc, _quote_type) do
    if current != "", do: Enum.reverse([current | acc]), else: Enum.reverse(acc)
  end

  defp parse_args("'" <> rest, current, acc, :none), do: parse_args(rest, current, acc, :single)
  defp parse_args("'" <> rest, current, acc, :single), do: parse_args(rest, current, acc, :none)
  defp parse_args("\"" <> rest, current, acc, :none), do: parse_args(rest, current, acc, :double)
  defp parse_args("\"" <> rest, current, acc, :double), do: parse_args(rest, current, acc, :none)

  defp parse_args("\\" <> <<char::utf8, rest::binary>>, current, acc, :double) when char in [?", ?\\],
    do: parse_args(rest, current <> <<char::utf8>>, acc, :double)

  defp parse_args("\\" <> <<char::utf8, rest::binary>>, current, acc, :double),
    do: parse_args(rest, current <> "\\" <> <<char::utf8>>, acc, :double)

  defp parse_args("\\" <> <<char::utf8, rest::binary>>, current, acc, :none),
    do: parse_args(rest, current <> <<char::utf8>>, acc, :none)

  defp parse_args(<<char::utf8, rest::binary>>, current, acc, :single),
    do: parse_args(rest, current <> <<char::utf8>>, acc, :single)

  defp parse_args(<<char::utf8, rest::binary>>, current, acc, :double),
    do: parse_args(rest, current <> <<char::utf8>>, acc, :double)

  defp parse_args(" " <> rest, "", acc, :none), do: parse_args(rest, "", acc, :none)
  defp parse_args(" " <> rest, current, acc, :none), do: parse_args(rest, "", [current | acc], :none)

  defp parse_args(<<char::utf8, rest::binary>>, current, acc, :none),
    do: parse_args(rest, current <> <<char::utf8>>, acc, :none)
end
