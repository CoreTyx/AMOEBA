# OpenTitan primitives, vendored

The async FIFO for the link's clock-domain crossing
(`docs/impl_plan_link_clocking.md` §4.2). Chosen over PULP `common_cells` and
the Cummings SNUG reference because it is already proven through a tapeout.

## Provenance

| File | Origin |
|---|---|
| `prim_fifo_async.sv` | **Verbatim** from lowRISC/opentitan `hw/ip/prim/rtl/`, master @ `8cfac43aa637fc6acdce3a290d8ffc6c82e3659c`, fetched 2026-10-02 |
| `LICENSE` | **Verbatim** — Apache 2.0, upstream root |
| `prim_assert.sv` | **Written for this repo.** Not upstream's. |
| `prim_flop_2sync.sv` | **Written for this repo.** Not upstream's. |

## Why two files are local rather than vendored

`prim_fifo_async.sv` has two dependencies and neither vendors cleanly:

- **`prim_assert.sv`** — upstream's includes four further headers plus
  `prim_flop_macros.sv`, and the chain keeps going. `prim_fifo_async` uses
  exactly two macros from it (`ASSERT_INIT`, `ASSERT`). Vendoring the chain for
  two macros is disproportionate, and it brings SVA that Verilator supports only
  in part. The local file defines those two and nothing else.
- **`prim_flop_2sync`** — an OpenTitan "abstract prim": the wrapper is generated
  by their build system and the implementation is chosen per technology, so
  there is no single file to copy. The local one is the two flops it reduces to.

The FIFO itself — the Gray-coded pointers, the full/empty derivation, the
depth calculation, the dec/gray conversion — is the part worth not writing by
hand, and that part is verbatim.

## Constraints this imposes

1. **`Depth` must be a power of two.** Enforced upstream by
   `ASSERT_INIT(ParamCheckDepth_A, ...)`, which the local `prim_assert.sv`
   keeps as a real elaboration check.
2. **`DepthW = $clog2(Depth+1)`** — at `Depth=16` the `wdepth_o`/`rdepth_o`
   outputs are 5 bits spanning 0..16.
3. **Each side needs its own reset**, asserted asynchronously and released
   synchronously *in its own domain*. Releasing one reset asynchronously to both
   sides can leave the two pointers mutually inconsistent; that is the classic
   failure of this structure.
4. **SDC**: the pointer synchronisers need `set_false_path` or
   `set_max_delay -datapath_only`, and the two stages of `prim_flop_2sync` must
   not be merged.
5. **Verification**: sweep *non-integer* clock ratios. 1:1 and 2:1 hide the
   crossing bugs this module exists to prevent.

## Updating

Re-fetch `prim_fifo_async.sv` from the path above and record the new SHA here.
Do not edit it locally — if it needs changing, the change belongs in a wrapper.
