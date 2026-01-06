defmodule TTY do
  @on_load :load_nif

  def load_nif do
    nif_path = :filename.join(:code.priv_dir(:codecrafters_shell), ~c"tty_nif")
    :erlang.load_nif(nif_path, 0)
  end

  def enable_raw_mode do
    raise "NIF enable_raw_mode/0 not loaded"
  end

  def disable_raw_mode do
    raise "NIF disable_raw_mode/0 not loaded"
  end
end
