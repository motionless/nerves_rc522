defmodule NervesRc522.RC522 do
  @moduledoc """
  I apologise in advance for the lack of documentation in this module.
  I mostly tried to port code from the C, C++, and Python versions of this driver
  and they had little to no documentation to explain why things were happening.

  As I figure out what's actually happening and why, I'll document it.

  Also apologies for commented-out code. It's stuff I'm not sure I need but
  don't want to get rid of it yet until I figure out what's going on.
  """

  use Bitwise
  require Logger
  alias Circuits.SPI
  alias Circuits.GPIO

  # MFRC522 docs 9.2 "Register Overview"
  @register %{
    command: 0x01,
    # toggle interrupt request control bits
    comm_ien: 0x02,
    # toggle interrupt request control bits
    div_ien: 0x03,
    # interrupt request bits
    comm_irq: 0x04,
    # interrupt request bits
    div_irq: 0x05,
    # error status of last command executed
    error: 0x06,
    # communication status bits
    status_1: 0x07,
    # receiver and transmitter status bits
    status_2: 0x08,
    # 64 byte FIFO buffer
    fifo_data: 0x09,
    # number of bytes stored in the FIFO register
    fifo_level: 0x0A,
    # level for FIFO under/overflow warning
    water_level: 0x0B,
    # miscellaneous control registers
    control: 0x0C,
    bit_framing: 0x0D,
    coll: 0x0E,
    # general mode for transmit and receive
    mode: 0x11,
    # transmission data rate and framing
    tx_mode: 0x12,
    # reception data rate and framing
    rx_mode: 0x13,
    # control logical behaviour of the antenna TX1 and TX2 pins
    tx_control: 0x14,
    # control setting of transmission moduleation
    tx_auto: 0x15,
    # select internal sources for the antenna driver
    tx_sel: 0x16,
    # receiver settings
    rx_sel: 0x17,
    # thresholds for bit decoder
    rx_threshold: 0x18,
    # demodulator settings
    demod: 0x19,
    # show the MSB and LSB values of the CRC calculation
    crc_result_h: 0x21,
    # show the MSB and LSB values of the CRC calculation
    crc_result_l: 0x22,
    mod_width: 0x24,
    # define settings for the internal timer
    t_mode: 0x2A,
    # define settings for the internal timer
    t_prescaler: 0x2B,
    # define the 16-bit timer reload value
    t_reload_h: 0x2C,
    t_reload_l: 0x2D,
    # show software version
    version: 0x37
  }
  @valid_registers Map.values(@register)

  # MFRC522 documentation 10.3 "Command overview"
  # Use with the "command" register to send commands to the PCD
  # PCD = Proximity Coupling Device. The RFID reader itself.
  @command %{
    # no action, cancels current command execution
    idle: 0x00,
    # stores 25 bytes into the internal buffer
    mem: 0x01,
    # generates a 10-byte random ID number
    gen_rand_id: 0x02,
    # activates the CRC coprocessor or performs a self test
    calc_crc: 0x03,
    # transmits data from the FIFO buffer
    transmit: 0x04,
    # can be used to modify the command register bits without affecting the command
    no_cmd_change: 0x07,
    # activates the receiver circuits
    receive: 0x08,
    # transmits data from the FIFO buffer to antenna and automatically activates the receiver after transmission
    transceive: 0x0C,
    # perform standard MIFARE auth as a reader
    mifare_auth: 0x0E,
    # perform a soft reset
    soft_reset: 0x0F
  }

  # Proximity Integrated Circuit Card (PICC)
  # The RFID Card or Tag using the ISO/IEC 14443A interface, for example Mifare or NTAG203.
  @picc %{
    # REQuest command, Type A. Invites PICCs in state IDLE to go to READY and prepare for anticollision or selection. 7 bit frame.
    request_idl: 0x26,
    # Wake-UP command, Type A. Invites PICCs in state IDLE and HALT to go to READY(*) and prepare for anticollision or selection. 7 bit frame.
    request_all: 0x52,
    # Anti collision/Select, Cascade Level 1
    anticoll: 0x93
  }

  # 9.3.2.5 Transmission control
  @tx_control %{
    antenna_on: 0x03
  }

  @gpio_reset_pin 25

  def initialize(spi) do
    hard_reset()

    spi
    |> write(@register.t_mode, 0x8D)
    |> write(@register.t_prescaler, 0x3E)
    |> write(@register.t_reload_l, 0x30)
    |> write(@register.t_reload_h, 0x00)
    |> write(@register.tx_auto, 0x40)
    |> write(@register.mode, 0x3D)
    |> antenna_on

    :ok
  end

  def halt(spi) do
    # TODO: implement. some code used this to tell the PCD (and/or PICC)
    # that we're done doing things with it.
    spi
  end

  @doc """
  See MFRC522 docs 9.3.4.8
  Bits 7 to 4 are the chiptype. Should always be "9" for MFRC522
  Bits 0 to 3 are the version
  """
  def hardware_version(spi) do
    data = read(spi, @register.version)

    %{
      chip_type: chip_type((data &&& 0xF0) >>> 4),
      version: data &&& 0x0F
    }
  end

  def read_tag_id_reliably(spi) do
    case read_tag_id(spi) do
      {:ok, data} ->
        {:ok, data}

      {:error, _data} ->
        case read_tag_id(spi) do
          {:ok, data} ->
            {:ok, data}

          _ ->
            {:error, nil}
        end
    end
  end

  def id_to_hex(data) do
    data
    |> Enum.map(fn n -> Integer.to_string(n, 16) end)
    |> Enum.join()
  end

  def read_tag_id(spi) do
    request(spi, @picc.request_idl)
    anticoll(spi)
    # uid
  end

  def read_full_tag_id(spi) do
    request(spi, @picc.request_all)
    anticoll(spi)
    # uid
  end

  def request(spi, request_mode) do
    # 0x07 start transmission
    write(spi, @register.bit_framing, 0x07)
    to_card(spi, @command.transceive, request_mode)
    #Logger.info("Status #{status}")
    #Logger.info("Request data #{inspect(data)}")
  end

  # def to_card_transceive(spi, data) do

  # end

  def to_card(spi, command, data) do
    # THESE ARE ONLY FOR COMMAND == transceive
    # irq_en = 0x77
    # wait_irq = 0x30   # RxIRq and IdleIRq

    spi
    # stop any active commands
    |> write(@register.command, @command.idle)
    # |> write(@register.comm_irq, 0x7F)                # clear all interrupt request bits
    # FlushBuffer = 1, FIFO init
    |> write(@register.fifo_level, 0x80)
    # |> write(@register.comm_ien, bor(0x80, irq_en))
    # |> clear_bit_mask(@register.comm_irq, 0x80)
    # |> set_bit_bask(@register.fifo_level, 0x80)
    |> write(@register.fifo_data, data)
    |> write(@register.command, command)

    if command == @command.transceive do
      set_bit_bask(spi, @register.bit_framing, 0x80)
    end

    # TODO: replace this with that loop that reads the Comm IRQ and does stuff
    :timer.sleep(50)

    data = read_fifo(spi)
    {:ok, data}
  end

  def anticoll(spi) do
    write(spi, @register.bit_framing, 0x00)

    {status, data} = to_card(spi, @command.transceive, [@picc.anticoll, 0x20])

    #Logger.info("Lenght #{Enum.count(data)}")
    #Logger.info("ID is #{inspect(data)}")
    # TODO: implement serial number check
    if Enum.count(data) == 5 do
      {status, data}
    else
      {:error, data}
    end

    # {status, data}
  end

  def hard_reset do
    {:ok, gpio} = GPIO.open(@gpio_reset_pin, :output)
    GPIO.write(gpio, 1)
    :timer.sleep(50)
    GPIO.close(gpio)
  end

  def soft_reset(spi), do: write(spi, @register.command, @command.soft_reset)

  def last_error(spi), do: read(spi, @register.error) &&& 0x1B

  def read_fifo(spi) do
    fifo_byte_count = read(spi, @register.fifo_level)
    read(spi, @register.fifo_data, fifo_byte_count)
  end

  def antenna_on(spi) do
    set_bit_bask(spi, @register.tx_control, @tx_control.antenna_on)
  end

  def antenna_off(spi) do
    clear_bit_mask(spi, @register.tx_control, @tx_control.antenna_on)
  end

  def set_bit_bask(spi, register, mask) when register in @valid_registers do
    state = read(spi, register)
    write(spi, register, bor(state, mask))
  end

  def clear_bit_mask(spi, register, mask) when register in @valid_registers do
    state = read(spi, register)
    value = state &&& bnot(mask)
    write(spi, register, value)
  end

  @doc """
  Write one or more bytes to the given register
  """
  def write(spi, register, value) when is_integer(value) do
    write(spi, register, [value])
  end

  def write(spi, register, values)
      when register in @valid_registers and
             is_list(values) do
    register = register <<< 1 &&& 0x7E

    Enum.each(values, fn value ->
      {:ok, _return} = SPI.transfer(spi, <<register, value>>)
    end)

    spi
  end

  @doc """
  Read the single byte value of the given register.
  The result of `SPI.transfer/2` is always the same length as the input.
  Since we have to send the register number and `0x00`, it means we always
  get two bytes back. The first byte appears to often be `0`, but sometimes other
  small values. But they have yet to seem relevant, so we discard it and consider
  only the second byte to be the value.
  """
  def read(spi, register) when register in @valid_registers do
    register = bor(0x80, register <<< 1 &&& 0x7E)
    {:ok, <<_, value>>} = SPI.transfer(spi, <<register, 0x00>>)
    value
  end

  @doc """
  Reads `bytes` number of bytes from the `register`. Returned as a list
  """
  def read(spi, register, bytes) when register in @valid_registers do
    Enum.map(1..bytes, fn _byte_index -> read(spi, register) end)
  end

  def card_id_to_number(data) do
    data
    # should only be five blocks, but just be sure
    |> Enum.take(5)
    |> Enum.reduce(0, fn x, acc -> acc * 256 + x end)
  end

  defp chip_type(9), do: :mfrc522
  defp chip_type(type), do: "unknown_#{type}"

  def card_type(0x04), do: :uid_incomplete
  def card_type(0x09), do: :mifare_mini
  def card_type(0x08), do: :mifare_1k
  def card_type(0x18), do: :mifare_4k
  def card_type(0x00), do: :mifare_ul
  def card_type(0x10), do: :mifare_plus
  def card_type(0x11), do: :mifare_plus
  def card_type(0x01), do: :tnp3xxx
  def card_type(0x20), do: :iso_14443_4
  def card_type(0x40), do: :iso_18092
  def card_type(_), do: :unknown
end
