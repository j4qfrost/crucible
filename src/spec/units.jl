# Unit handling for the MD IR.
#
# Hard rule: the LLM emits raw numbers tagged with units in the IR (e.g.
# `temperature_K`). The renderer is the *only* code that converts them. Never
# let the LLM do unit math.
#
# We rely on Unitful for in-Julia conversions and keep the IR's wire-format
# units fixed and named in the field name (Kelvin, ns, fs, kJ/mol/nm^2, bar).

using Unitful

const PROVENANCE_SOURCES = (:paper, :paper_default, :assumed, :user, :runtime_default)

# Wire-format units locked into the schema. Don't change without a schema
# version bump — these are part of the LLM contract.
const WIRE_TEMPERATURE = u"K"
const WIRE_PRESSURE    = u"bar"
const WIRE_DURATION    = u"ns"
const WIRE_TIMESTEP    = u"fs"
const WIRE_FRICTION    = u"ps^-1"
const WIRE_FORCEK      = u"kJ/mol/nm^2"
const WIRE_LENGTH      = u"nm"

# Helpers for renderer code — keep all unit conversion in one place so a
# rendering bug can't be smuggled past unit-checked types.

ns_to_steps(duration_ns::Real, dt_fs::Real) = round(Int, (duration_ns * 1_000_000) / dt_fs)

ps_to_steps(duration_ps::Real, dt_fs::Real) = round(Int, (duration_ps * 1_000) / dt_fs)
