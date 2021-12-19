defmodule NervesRc522.CardScanner do
  use GenServer
  require Logger
  alias NervesRc522.RC522

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(_state) do
    Logger.info("Start CardScanner Server")

    state = %{spi: nil, listener: start_listener()}

    Process.send_after(self(), :init, 1 * 1000)
    {:ok, state}
  end

  defp start_listener do
    case Application.get_env(:nerves_rc522, :listener, nil) do
      nil ->
        Logger.warn("No listener for CardScanner configured.")
        nil
      listener ->
        case listener.start_link([]) do
          {:ok, pid} ->
            pid
          _ ->
            nil
        end
    end
  end

  def handle_info(:work, state) do
    case RC522.read_tag_id_reliably(state.spi) do
      {:ok, tag} ->
        Logger.info("tag read #{tag |> RC522.id_to_hex()}")
        trigger(tag |> RC522.id_to_hex())
      _ ->
        nil
    end

    # Reschedule once more
    schedule_work(Application.get_env(:nerves_rc522, :scan_interval))
    {:noreply, state}
  end

  def handle_info({:trigger, tag_id}, state) do
    if state.listener != nil do
      GenServer.cast(state.listener, {:receive_tag_id, tag_id})
      #GenServer.cast(Meatlug, :read_card)
      GenServer.cast(Meatlug, :demo)
    end
    {:noreply, state}
  end

  def handle_info(:init, state) do
    Logger.info("Initialize RC522")

    Circuits.SPI.open("spidev0.0")
    |> init_spi_device(state)
  end

  defp init_spi_device({:ok, spi}, state) do
    RC522.initialize(spi)
    Logger.info("RC522 initialized #{inspect(spi, pretty: true)}")

    schedule_work(Application.get_env(:nerves_rc522, :scan_interval))
    {:noreply, %{state | spi: spi}}
  end

  defp init_spi_device({:error, :access_denied}, state) do
    Logger.error("RC522 initialization failed ")
    {:noreply, state}
  end

  def trigger(tag_id) do
    Process.send(self(), {:trigger, tag_id}, [])

    #SonosNerves.CardMapper.trigger_action(tag_id)
  end

  def schedule_work(interval) do
    Process.send_after(self(), :work, interval)
  end
end
