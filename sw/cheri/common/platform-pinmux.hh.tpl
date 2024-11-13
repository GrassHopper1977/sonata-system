// SPDX-FileCopyrightText: lowRISC contributors
// SPDX-License-Identifier: Apache-2.0

${"#"}pragma once
${"#"}include <debug.hh>
${"#"}include <stdint.h>
${"#"}include <utils.hh>
${"#"}include <cheri.hh>

namespace SonataPinmux {
/// The number of pin sinks (pin outputs)
static constexpr size_t NumPinSinks = ${len(output_pins)};

/// The number of block sinks (block inputs)
static constexpr size_t NumBlockSinks = ${len(output_block_ios)};

/// Flag to set when debugging the driver for UART log messages.
static constexpr bool DebugDriver = false;

/// Helper for conditional debug logs and assertions.
using Debug = ConditionalDebug<DebugDriver, "Pinmux">;

/**
 * Each pin sink is configured by an 8-bit register. This enum maps pin sink
 * names to the offset of their configuration registers. The offsets are relative
 * to the first pin sink register.
 *
 * Documentation sources:
 * 1. https://lowrisc.github.io/sonata-system/doc/ip/pinmux/
 * 2. https://github.com/lowRISC/sonata-system/blob/4b72d8c07c727846c6ccb27754352388f3b2ac9a/data/pins_sonata.xdc
 * 3. https://github.com/newaetech/sonata-pcb/blob/649b11c2fb758f798966605a07a8b6b68dd434e9/sonata-schematics-r09.pdf
 */
enum class PinSink : uint16_t {
% for output_idx, (pin, _, _) in enumerate(output_pins):
  ${pin.name} = ${f"{output_idx:#0{5}x}"},
% endfor
};

/**
 * Each block sink is configured by an 8-bit register. This enum maps block sink
 * names to the offset of their configuration registers. The offsets are relative
 * to the first block sink register.
 *
 * For GPIO block reference:
 *   gpio_0 = Raspberry Pi Header Pins
 *   gpio_1 = Arduino Shield Header Pins
 *   gpio_2 = Pmod0 Pins
 *   gpio_3 = Pmod1 Pins
 *   gpio_4 = PmodC Pins
 *
 * Documentation source:
 * https://lowrisc.github.io/sonata-system/doc/ip/pinmux/
 */
enum class BlockSink : uint16_t {
% for input_idx, (block_io, possible_pins, num_options) in enumerate(output_block_ios):
  ${block_io.doc_name.replace("[","_").replace(".","_").replace("]","")} = ${f"{input_idx:#0{5}x}"}, 
% endfor
};

/**
 * Returns the number of sources available for a pin sink (output pin).
 *
 * @param pin_sink The pin sink to query.
 * @returns The number of sources available for the given sink.
 */
static constexpr uint8_t sources_number(PinSink pin_sink) {
  switch (pin_sink) {
<%
  prev_num_options = 0
%>
% for (pin, _, num_options) in filter(lambda pin: pin[2] > 2, sorted(output_pins, key=lambda pin: pin[2], reverse=True)):
  % if prev_num_options != 0 and prev_num_options != num_options:
	  return ${prev_num_options};
  % endif
  <%
	  prev_num_options = num_options
  %>      case PinSink::${pin.name}:
% endfor
% if prev_num_options != 0:
	  return ${prev_num_options};
% endif
	default:
	  return 2;
  }
}

/**
 * Returns the number of sources available for a block sink (block input).
 *
 * @param block_sink The block sink to query.
 * @returns The number of sources available for the given sink.
 */
static constexpr uint8_t sources_number(BlockSink block_sink) {
  switch (block_sink) {
<%
  prev_num_options = 0
%>
% for (block_io, _, num_options) in filter(lambda block: block[2] > 2, sorted(output_block_ios, key=lambda block: block[2], reverse=True)):
  % if prev_num_options != 0 and prev_num_options != num_options:
	  return ${prev_num_options};
  % endif
  <%
	  prev_num_options = num_options
  %>      case BlockSink::${block_io.doc_name.replace("[","_").replace(".","_").replace("]","")}:
% endfor
% if prev_num_options != 0:
	  return ${prev_num_options};
% endif
	default:
	  return 2;
  }
}

/**
 * A handle to a sink configuration register. This can be used to select
 * the source of the handle's associated sink.
 */
template <typename SinkEnum>
struct Sink {
  CHERI::Capability<volatile uint8_t> reg;
  const SinkEnum sink;

  /**
   * Select a source to connect to the sink.
   *
   * To see the sources available for a given sink see the Sonata system
   * documentation:
   * https://lowrisc.github.io/sonata-system/doc/ip/pinmux/
   *
   * Note, source 0 disconnects the sink from any source disabling it,
   * and source 1 is the default source for any given sink.
   */
  bool select(uint8_t source) {
    if (source >= sources_number(sink)) {
      Debug::log("Selected source not within the range of valid sources.");
      return false;
    }
    *reg = 1 << source;
    return true;
  }

  /// Disconnect the sink from all available sources.
  void disable() { *reg = 0b01; }

  /// Reset the sink to it's default source.
  void default_selection() { *reg = 0b10; }
};

namespace {
template <typename SinkEnum>
// This is used by `BlockSinks` and `PinSinks`
// to return a capability to a single sink's configuration register.
inline Sink<SinkEnum> _get_sink(volatile uint8_t *base_register, const SinkEnum sink) {
  CHERI::Capability reg = {base_register + static_cast<ptrdiff_t>(sink)};
  reg.bounds()          = sizeof(uint8_t);
  return Sink<SinkEnum>{reg, sink};
};
}  // namespace

/**
 * A driver for the Sonata system's pin multiplexed output pins.
 *
 * The Sonata's Pin Multiplexer (pinmux) has two sets of registers. The pin sink
 * registers and the block sink registers. This structure provides access to the
 * pin sinks registers. Pin sinks are output onto the Sonata system's pins that
 * can be connected to a number block outputs (their sources). The sources a sink
 * can connect to are limited. See the documentation for the possible sources for
 * a given pin:
 *
 * https://lowrisc.github.io/sonata-system/doc/ip/
 */
struct PinSinks : private utils::NoCopyNoMove {
  volatile uint8_t registers[NumPinSinks];

  /// Returns a handle to a pin sink (an output pin).
  Sink<PinSink> get(PinSink sink) volatile {
    return _get_sink<PinSink>(registers, sink);
  };
};

/**
 * A driver for the Sonata system's pin multiplexed block inputs.
 *
 * The Sonata's Pin Multiplexer (pinmux) has two sets of registers. The pin sink
 * registers and the block sink registers. This structure provides access to the
 * block sinks registers. Block sinks are inputs into the Sonata system's devices
 * that can be connected to a number system input pins (their sources). The sources
 * a sink can connect to are limited. See the documentation for the possible sources
 * for a given pin:
 *
 * https://lowrisc.github.io/sonata-system/doc/ip/
 */
struct BlockSinks : private utils::NoCopyNoMove {
  volatile uint8_t registers[NumBlockSinks];

  /// Returns a handle to a block sink (a block input).
  Sink<BlockSink> get(BlockSink sink) volatile {
    return _get_sink<BlockSink>(registers, sink);
  };
};
}  // namespace SonataPinmux
