# AT Protocol record-authoring for Crucible. Currently scoped to app.hekate.*
# records (paper-review session announcements).
#
# Default behaviour for app.hekate.event is dry-run; live publishing requires
# CRUCIBLE_HEKATE_PUBLISH_EVENTS=1. See ADR 0002 in
# ~/Projects/hekate/docs/adr/0002-smoke-signal-relationship.md.

module ATProto

using Dates
using HTTP
using JSON3
using TOML

import ..Crucible

include("Errors.jl")
include("Config.jl")
include("Lexicon.jl")
include("Records.jl")
include("Client.jl")
include("HekateBootstrap.jl")
include("HekatePublisher.jl")

export HekateConfig, Session, ATProtoError, Violation,
       load_config, default_config_path, is_publish_ready, save_bootstrap!,
       create_session, create_record, get_record, list_records, delete_record,
       set_http_transport!, reset_http_transport!,
       build_venue, build_slot, build_recurrence, build_event,
       validate_record, has_errors, format_violations, assert_valid!,
       bootstrap_venue!, create_slot!,
       ReviewSessionRequest, PublishResult,
       publish_review_session, publish_review_session_from_run,
       resolve_next_open_slot

end # module ATProto
