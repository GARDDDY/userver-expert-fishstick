set(_bench_pch_all
    <userver/components/component.hpp>
    <userver/server/handlers/http_handler_base.hpp>
    <userver/storages/postgres/component.hpp>
    <userver/storages/postgres/cluster.hpp>
    <userver/storages/mongo/component.hpp>
    <userver/storages/mongo/pool.hpp>
    <userver/ugrpc/server/service_component_base.hpp>
    <userver/ugrpc/client/client_factory_component.hpp>
)
set(_bench_pch_proto
    <userver/components/component.hpp>
    <userver/ugrpc/server/service_component_base.hpp>
    <userver/ugrpc/client/client_factory_component.hpp>
)

if(DEFINED BENCH_PCH AND NOT BENCH_PCH STREQUAL "")
    target_precompile_headers(bench_service_proto PRIVATE ${_bench_pch_proto})
    set(_bench_users bench_service bench_service_unittest bench_service_benchmark)

    if(BENCH_PCH STREQUAL "per_target")
        target_precompile_headers(bench_service_objs PRIVATE ${_bench_pch_all})
        foreach(_t IN LISTS _bench_users)
            target_precompile_headers(${_t} PRIVATE ${_bench_pch_all})
        endforeach()
    elseif(BENCH_PCH STREQUAL "shared")
        target_precompile_headers(bench_service_objs PRIVATE ${_bench_pch_all})
        foreach(_t IN LISTS _bench_users)
            target_precompile_headers(${_t} REUSE_FROM bench_service_objs)
        endforeach()
    else()
        message(FATAL_ERROR "unknown BENCH_PCH='${BENCH_PCH}'")
    endif()
endif()
