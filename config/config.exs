import Config

alias Ash.Type.UUID
alias AshClickhouse.Type.ChAtom
alias AshClickhouse.Type.ChBool
alias AshClickhouse.Type.ChDate
alias AshClickhouse.Type.ChDate32
alias AshClickhouse.Type.ChDateTime
alias AshClickhouse.Type.ChDateTime64
alias AshClickhouse.Type.ChDecimal
alias AshClickhouse.Type.ChDecimal128
alias AshClickhouse.Type.ChDecimal256
alias AshClickhouse.Type.ChDecimal32
alias AshClickhouse.Type.ChDecimal64
alias AshClickhouse.Type.ChFixedString
alias AshClickhouse.Type.ChFloat32
alias AshClickhouse.Type.ChFloat64
alias AshClickhouse.Type.ChInt128
alias AshClickhouse.Type.ChInt16
alias AshClickhouse.Type.ChInt256
alias AshClickhouse.Type.ChInt32
alias AshClickhouse.Type.ChInt64
alias AshClickhouse.Type.ChInt8
alias AshClickhouse.Type.ChIPv4
alias AshClickhouse.Type.ChIPv6
alias AshClickhouse.Type.ChJSON
alias AshClickhouse.Type.ChMap
alias AshClickhouse.Type.ChMultiPolygon
alias AshClickhouse.Type.ChPoint
alias AshClickhouse.Type.ChPolygon
alias AshClickhouse.Type.ChRing
alias AshClickhouse.Type.ChSimpleAggregateFunction
alias AshClickhouse.Type.ChString
alias AshClickhouse.Type.ChTuple
alias AshClickhouse.Type.ChUint128
alias AshClickhouse.Type.ChUint16
alias AshClickhouse.Type.ChUint256
alias AshClickhouse.Type.ChUint32
alias AshClickhouse.Type.ChUint64
alias AshClickhouse.Type.ChUint8
alias AshClickhouse.Type.ChUUID
alias AshClickhouse.Type.ChVariant
alias AshClickhouse.Type.ChTime64

ch_custom_types =
  [
    ch_atom: ChAtom,
    ch_bool: ChBool,
    ch_date: ChDate,
    ch_date32: ChDate32,
    ch_time64: ChTime64,
    ch_datetime: ChDateTime,
    ch_datetime64: ChDateTime64,
    ch_decimal: ChDecimal,
    ch_decimal32: ChDecimal32,
    ch_decimal64: ChDecimal64,
    ch_decimal128: ChDecimal128,
    ch_decimal256: ChDecimal256,
    ch_fixed_string: ChFixedString,
    ch_float32: ChFloat32,
    ch_float64: ChFloat64,
    ch_ipv4: ChIPv4,
    ch_ipv6: ChIPv6,
    ch_int8: ChInt8,
    ch_int16: ChInt16,
    ch_int32: ChInt32,
    ch_int64: ChInt64,
    ch_int128: ChInt128,
    ch_int256: ChInt256,
    ch_json: ChJSON,
    ch_map: ChMap,
    ch_point: ChPoint,
    ch_ring: ChRing,
    ch_polygon: ChPolygon,
    ch_multipolygon: ChMultiPolygon,
    ch_string: ChString,
    ch_uint8: ChUint8,
    ch_uint16: ChUint16,
    ch_uint32: ChUint32,
    ch_uint64: ChUint64,
    ch_uint128: ChUint128,
    ch_uint256: ChUint256,
    ch_uuid: ChUUID,
    ch_variant: ChVariant,
    ch_tuple: ChTuple,
    ch_simple_aggregate_function: ChSimpleAggregateFunction
  ]

config :ash, :custom_types, ch_custom_types

config :ash, :compatible_foreign_key_types, [
  {Ash.Type.UUID, AshClickhouse.Type.ChUUID}
]

if Mix.env() == :test do
  config :ash_clickhouse,
    ecto_repos: [AshClickhouse.TestRepo],
    ash_domains: [AshClickhouse.Test.Domain]

  config :ash_clickhouse, AshClickhouse.TestRepo,
    url: System.get_env("CLICKHOUSE_URL") || "http://default:@localhost:8123/default"
end
