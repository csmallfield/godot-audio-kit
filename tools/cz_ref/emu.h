// SPDX-License-Identifier: BSD-3-Clause
// Just enough of MAME's device framework for src/devices/sound/upd933.cpp to build unchanged
// outside MAME: a device with a clock, a one-channel stream the harness pulls a sample at a
// time, a timer that does nothing (the harness polls the envelopes itself) and no save states.
#pragma once
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <algorithm>

typedef uint8_t u8; typedef uint16_t u16; typedef uint32_t u32; typedef uint64_t u64;
typedef int8_t s8; typedef int16_t s16; typedef int32_t s32; typedef int64_t s64;

template <typename T> constexpr T BIT(T x, int n) { return (x >> n) & T(1); }
template <typename T> constexpr T BIT(T x, int n, int w) { return (x >> n) & ((T(1) << w) - 1); }

#define ATTR_COLD
#define NAME(x) x
#define STRUCT_MEMBER(s, m) s
#define FUNC(x) 0
#define TIMER_CALLBACK_MEMBER(name) void name(s32 param)
#define DECLARE_DEVICE_TYPE(Type, Class) extern int Type;
#define DEFINE_DEVICE_TYPE(Type, Class, Short, Full) int Type = 0;

struct machine_config {};
struct attotime { static const attotime never; };
inline const attotime attotime::never{};

struct running_machine {
	bool side_effects_disabled() const { return false; }
	const char *describe_context() const { return ""; }
	u32 rand() { seed = seed * 1103515245u + 12345u; return (seed >> 16) & 0x7fff; }
	u32 seed = 1;
};

struct emu_timer { void adjust(const attotime &) {} };

class sound_stream {
public:
	int samples() const { return n; }
	void put_int_clamp(int, int i, s32 v, s32 range) { out[i] = float(std::clamp(v, -range, range - 1)) / float(range); }
	void update() {}
	void set_sample_rate(u32) {}
	int n = 0; float *out = nullptr;
};

struct devcb_write_line {
	template <typename T> devcb_write_line(T &) {}
	void operator()(int) {}
	devcb_write_line &bind() { return *this; }
};

class device_t {
public:
	device_t(const machine_config &, int, const char *, device_t *, u32 clock) : m_clock(clock) {}
	virtual ~device_t() = default;
	u32 clock() const { return m_clock; }
	running_machine &machine() { return m_machine; }
	template <typename T> void save_item(const T &) {}
	template <typename... A> void logerror(const char *, A...) {}
	template <typename F, typename O> emu_timer *timer_alloc(F, O) { return &m_timer; }
	attotime clocks_to_attotime(u64) const { return attotime(); }
protected:
	virtual void device_start() {}
	virtual void device_reset() {}
	virtual void device_clock_changed() {}
	u32 m_clock;
	running_machine m_machine;
	emu_timer m_timer;
};

class device_sound_interface {
public:
	device_sound_interface(const machine_config &, device_t &) {}
	virtual ~device_sound_interface() = default;
	sound_stream *stream_alloc(int, int, u32) { return &m_s; }
	virtual void sound_stream_update(sound_stream &stream) = 0;
	sound_stream m_s;
};
