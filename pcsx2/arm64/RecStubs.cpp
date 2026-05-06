// SPDX-FileCopyrightText: 2002-2025 PCSX2 Dev Team
// SPDX-License-Identifier: GPL-3.0

#include "common/Console.h"
#include "MTVU.h"
#include "SaveState.h"
#include "vtlb.h"

#include "common/Assertions.h"

// TODO: implement using ARM64 load/store instruction emitters with VIXL
// This function is called when the dynamic VTLB needs to backpatch a
// memory access in JIT-compiled code. On ARM64, emit the appropriate
// load/store instructions (LDR/STR with address calculation) and hook
// them into the code cache.
void vtlb_DynBackpatchLoadStore(uptr code_address, u32 code_size, u32 guest_pc, u32 guest_addr, u32 gpr_bitmask, u32 fpr_bitmask, u8 address_register, u8 data_register, u8 size_in_bits, bool is_signed, bool is_load, bool is_fpr)
{
  pxFailRel("Not implemented.");
}

// TODO: implement using proper VU recompiler state serialization
// On ARM64, the VU JIT (when implemented via VIXL) will have:
// - VU micro program code cache state
// - VU register allocation state
// - Pipeline state (status registers, PC, etc.)
// This function should freeze/thaw that state for save states.
bool SaveStateBase::vuJITFreeze()
{
	if(IsSaving())
		vu1Thread.WaitVU();

	Console.Warning("recompiler state is stubbed in arm64!");

	// HACK!!

	// size of microRegInfo structure
	std::array<u8,96> empty_data{};
	Freeze(empty_data);
	Freeze(empty_data);
	return true;
}
