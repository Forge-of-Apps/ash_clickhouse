defmodule AshClickhouse.CreateTest do
  use AshClickhouse.RepoCase, async: true
  alias AshClickhouse.Test.Resource.User
  alias AshClickhouse.Test.Resource.Organization
  alias AshClickhouse.Test.Resource.OrganizationUser
  alias TestRepo

  require Ash.Query

  setup do
    TestRepo.query("TRUNCATE TABLE users")
    TestRepo.query("TRUNCATE TABLE organizations")
    TestRepo.query("TRUNCATE TABLE users_organizations")
    TestRepo.query("TRUNCATE TABLE all_types")
    :ok
  end

  describe "User resource create tests" do
    test "seeding data works" do
      Ash.Seed.seed!(%User{name: "Fred"})
    end

    test "creates insert" do
      params = %{
        name: "Fred",
        email: "fred@example.com",
        age: 30,
        score: :rand.uniform(),
        is_active: true
      }

      assert {:ok, %User{}} =
               User
               |> Ash.Changeset.for_create(:create, params)
               |> Ash.create()

      assert [%{name: "Fred"}] =
               User
               |> Ash.Query.sort(:name)
               |> Ash.read!()
    end

    test "creates user with organizations using manage_relationship" do
      org_params = %{name: "Org 1", industry: "Tech", employee_count: 100, founded_year: 2020}

      {:ok, org} =
        Organization
        |> Ash.Changeset.for_create(:create, org_params)
        |> Ash.create()

      user_params = %{
        name: "Alice",
        email: "alice@example.com",
        age: 28,
        score: 99.9,
        is_active: true
      }

      changeset =
        User
        |> Ash.Changeset.for_create(:create, user_params)
        |> Ash.Changeset.manage_relationship(:organizations, [org], type: :append_and_remove)

      assert {:ok, %User{} = user} = Ash.create(changeset)
      assert [%{name: "Org 1"}] = user.organizations

      user_id = user.id
      org_id = org.id

      assert [%{user_id: ^user_id, organization_id: ^org_id, role: :member}] =
               OrganizationUser
               |> Ash.Query.filter(user_id == ^user.id and organization_id == ^org.id)
               |> Ash.read!()
    end

    test "bulk create users" do
      params_list =
        [
          %{
            name: "User1",
            email: "user1@example.com",
            age: 20,
            score: 10.5,
            is_active: true
          },
          %{
            name: "User2",
            email: "user2@example.com",
            age: 25,
            score: 20.0,
            is_active: false
          },
          %{
            name: "User3",
            email: "user3@example.com",
            age: 30,
            score: 30.1,
            is_active: true
          }
        ]

      assert %Ash.BulkResult{
               status: :success,
               errors: nil,
               records: nil,
               notifications: nil,
               error_count: 0
             } = Ash.bulk_create(params_list, User, :create)

      assert [
               %User{
                 name: "User1",
                 email: "user1@example.com",
                 age: 20,
                 score: 10.5,
                 is_active: true,
                 inserted_at: %DateTime{},
                 updated_at: %DateTime{}
               },
               %User{
                 name: "User2",
                 email: "user2@example.com",
                 age: 25,
                 score: 20.0,
                 is_active: false,
                 inserted_at: %DateTime{},
                 updated_at: %DateTime{}
               },
               %User{
                 name: "User3",
                 email: "user3@example.com",
                 age: 30,
                 score: 30.1,
                 is_active: true,
                 inserted_at: %DateTime{},
                 updated_at: %DateTime{}
               }
             ] =
               User
               |> Ash.Query.sort(:name)
               |> Ash.read!()
    end

    test "fails to create user with invalid parameters" do
      # Missing required :name and :email fields, and invalid :age type
      params = %{
        age: 20.5
      }

      assert {:error,
              %Ash.Error.Invalid{
                bread_crumbs: ["Error returned from: AshClickhouse.Test.Resource.User.create"],
                errors: [
                  %Ash.Error.Changes.InvalidAttribute{
                    field: :age,
                    message: "must be an integer between 0 and (2^8 - 1)",
                    private_vars: nil,
                    value: 20.5,
                    has_value?: true,
                    splode: Ash.Error,
                    bread_crumbs: [
                      "Error returned from: AshClickhouse.Test.Resource.User.create"
                    ],
                    vars: [],
                    path: [],
                    class: :invalid
                  }
                ]
              }} =
               User
               |> Ash.Changeset.for_create(:create, params)
               |> Ash.create()
    end
  end

  describe "Organization resource create tests" do
    test "creates insert" do
      params = %{
        name: "Tech Corp",
        industry: "Technology",
        employee_count: 500,
        founded_year: 2010
      }

      assert {:ok, %Organization{name: "Tech Corp"}} =
               Organization
               |> Ash.Changeset.for_create(:create, params)
               |> Ash.create()

      assert [%{name: "Tech Corp"}] =
               Organization
               |> Ash.Query.sort(:name)
               |> Ash.read!()
    end

    test "creates organization with users using manage_relationship" do
      user_params = %{
        name: "Bob",
        email: "bob@example.com",
        age: 35,
        score: 88.5,
        is_active: true
      }

      {:ok, user} =
        User
        |> Ash.Changeset.for_create(:create, user_params)
        |> Ash.create()

      org_params = %{
        name: "Org with Bob",
        industry: "Finance",
        employee_count: 50,
        founded_year: 2015
      }

      changeset =
        Organization
        |> Ash.Changeset.for_create(:create, org_params)
        |> Ash.Changeset.manage_relationship(:users, [user], type: :append_and_remove)

      assert {:ok, %Organization{} = org} = Ash.create(changeset)
      assert [%{name: "Bob"}] = org.users

      org_id = org.id
      user_id = user.id

      assert [%{user_id: ^user_id, organization_id: ^org_id, role: :member}] =
               OrganizationUser
               |> Ash.Query.filter(user_id == ^user.id and organization_id == ^org.id)
               |> Ash.read!()
    end

    test "organization can be created without users" do
      params = %{
        name: "Solo Org",
        industry: "Education",
        employee_count: 10,
        founded_year: 2022
      }

      assert {:ok, %Organization{name: "Solo Org", users: []}} =
               Organization
               |> Ash.Changeset.for_create(:create, params)
               |> Ash.Changeset.load(:users)
               |> Ash.create()

      assert [%Organization{name: "Solo Org", users: []}] =
               Organization
               |> Ash.Query.filter(name == "Solo Org")
               |> Ash.Query.load(:users)
               |> Ash.read!()
    end

    test "organization can have multiple users" do
      user1_params = %{
        name: "Carol",
        email: "carol@example.com",
        age: 29,
        score: 77.7,
        is_active: true
      }

      user2_params = %{
        name: "Dave",
        email: "dave@example.com",
        age: 40,
        score: 66.6,
        is_active: false
      }

      {:ok, user1} =
        User
        |> Ash.Changeset.for_create(:create, user1_params)
        |> Ash.create()

      {:ok, user2} =
        User
        |> Ash.Changeset.for_create(:create, user2_params)
        |> Ash.create()

      org_params = %{
        name: "Org with Many",
        industry: "Retail",
        employee_count: 200,
        founded_year: 2000
      }

      changeset =
        Organization
        |> Ash.Changeset.for_create(:create, org_params)
        |> Ash.Changeset.manage_relationship(:users, [user1, user2], type: :append_and_remove)

      assert {:ok, %Organization{} = org} = Ash.create(changeset)
      assert Enum.sort(Enum.map(org.users, & &1.name)) == ["Carol", "Dave"]

      org_id = org.id
      user1_id = user1.id
      user2_id = user2.id

      assert [
               %{user_id: ^user1_id, organization_id: ^org_id, role: :member},
               %{user_id: ^user2_id, organization_id: ^org_id, role: :member}
             ] =
               OrganizationUser
               |> Ash.Query.filter(organization_id == ^org.id)
               |> Ash.Query.sort(:inserted_at)
               |> Ash.read!()
    end
  end

  describe "AllTypes resource create tests" do
    alias AshClickhouse.Test.Resource.AllTypes

    @tag timeout: 100_000
    test "creates insert with all types" do
      params = %{
        string_attr: "Test String",
        nullable_string_attr: nil,
        low_cardinality_string_attr: "LowCard",
        low_cardinality_nullable_string_attr: nil,
        fixed_string_attr: String.duplicate("A", 16),
        nullable_fixed_string_attr: nil,
        int8_attr: 127,
        nullable_int8_attr: nil,
        int16_attr: 32_767,
        nullable_int16_attr: nil,
        int32_attr: 2_147_483_647,
        nullable_int32_attr: nil,
        int64_attr: 9_223_372_036_854_775_807,
        nullable_int64_attr: nil,
        int128_attr: 170_141_183_460_469_231_731_687_303_715_884_105_727,
        nullable_int128_attr: nil,
        int256_attr: 1,
        nullable_int256_attr: nil,
        uint8_attr: 255,
        nullable_uint8_attr: nil,
        uint16_attr: 65_535,
        nullable_uint16_attr: nil,
        uint32_attr: 4_294_967_295,
        nullable_uint32_attr: nil,
        uint64_attr: 18_446_744_073_709_551_615,
        nullable_uint64_attr: nil,
        uint128_attr: 340_282_366_920_938_463_463_374_607_431_768_211_455,
        nullable_uint128_attr: nil,
        uint256_attr: 1,
        nullable_uint256_attr: nil,
        float32_attr: 3.14,
        nullable_float32_attr: nil,
        float64_attr: 2.71828,
        nullable_float64_attr: nil,
        bool_attr: true,
        atom_attr: :some_atom,
        date_attr: ~D[2024-01-01],
        nullable_date_attr: nil,
        date32_attr: ~D[2024-01-01],
        datetime_attr: ~U[2024-01-01 12:00:00Z],
        datetime64_attr: ~U[2024-01-01 12:00:00Z],
        decimal_attr: Decimal.new("0.67"),
        decimal32_attr: Decimal.new("0.123456789"),
        nullable_decimal32_attr: nil,
        decimal64_attr: Decimal.new("0.123456789123456789"),
        nullable_decimal64_attr: nil,
        decimal128_attr: Decimal.new("0.12345678912345678912345678912345678912", max_digits: 76),
        nullable_decimal128_attr: nil,
        decimal256_attr:
          Decimal.new(
            "0.1234567891234567891234567891234567891234567891234567891234567891234567891234",
            max_digits: 76
          ),
        nullable_decimal256_attr: nil,
        json_attr: %{"foo" => "bar"},
        nullable_json_attr: nil,
        map_attr: %{"foo" => "value1", "bar" => "value2", "baz" => "value3"},
        ipv4_attr: "192.168.1.1",
        nullable_ipv4_attr: nil,
        ipv6_attr: "2001:0db8:85a3:0000:0000:8a2e:0370:7334",
        nullable_ipv6_attr: nil,
        uuid_attr: "550e8400-e29b-41d4-a716-446655440000",
        nullable_uuid_attr: nil,
        tuple_attr: {"foo", 42, true},
        point_attr: {12.34, 56.78},
        ring_attr: [
          {1.0, 2.0},
          {3.0, 4.0},
          {5.0, 6.0}
        ],
        polygon_attr: [
          [
            {1.0, 2.0},
            {3.0, 4.0},
            {5.0, 6.0}
          ]
        ],
        multipolygon_attr: [
          [
            [
              {1.0, 2.0},
              {3.0, 4.0},
              {5.0, 6.0}
            ]
          ],
          [
            [
              {7.0, 8.0},
              {9.0, 10.0},
              {11.0, 12.0}
            ]
          ]
        ],
        simple_agg_func_attr: 123,
        variant_attr: "string ou 42 ou true",
        array_of_string_attr: ["foo", "bar", "baz"],
        array_of_low_cardinality_string_attr: ["foo", "bar", "baz"],
        array_of_nullable_string_attr: ["foo", "bar", "baz"],
        array_of_low_cardinality_nullable_string_attr: ["foo", "bar", "baz"],
        array_of_int32_attr: [1, 2, 3],
        array_of_nullable_int32_attr: [1, 2, 3],
        array_of_int64_attr: [1, 2, 3],
        array_of_nullable_int64_attr: [1, 2, 3],
        array_of_uint32_attr: [1, 2, 3],
        array_of_nullable_uint32_attr: [1, 2, 3],
        array_of_uint64_attr: [1, 2, 3],
        array_of_nullable_uint64_attr: [1, 2, 3],
        array_of_float32_attr: [1.0, 2.0, 3.0],
        array_of_nullable_float32_attr: [1.0, 2.0, 3.0],
        array_of_float64_attr: [1.0, 2.0, 3.0],
        array_of_nullable_float64_attr: [1.0, 2.0, 3.0],
        array_of_bool_attr: [true, false, true],
        array_of_date_attr: [~D[2024-01-01], ~D[2024-01-02], ~D[2024-01-03]],
        array_of_nullable_date_attr: [~D[2024-01-01], ~D[2024-01-02], ~D[2024-01-03]],
        array_of_date32_attr: [~D[2024-01-01], ~D[2024-01-02], ~D[2024-01-03]],
        array_of_nullable_date32_attr: [~D[2024-01-01], ~D[2024-01-02], ~D[2024-01-03]],
        array_of_datetime_attr: [
          ~U[2024-01-01 12:00:00Z],
          ~U[2024-01-02 12:00:00Z],
          ~U[2024-01-03 12:00:00Z]
        ],
        array_of_nullable_datetime_attr: [
          ~U[2024-01-01 12:00:00Z],
          ~U[2024-01-02 12:00:00Z],
          ~U[2024-01-03 12:00:00Z]
        ],
        array_of_datetime64_attr: [
          ~U[2024-01-01 12:00:00.000000Z],
          ~U[2024-01-02 12:00:00.000000Z],
          ~U[2024-01-03 12:00:00.000000Z]
        ],
        array_of_nullable_datetime64_attr: [
          ~U[2024-01-01 12:00:00.000000Z],
          ~U[2024-01-02 12:00:00.000000Z],
          ~U[2024-01-03 12:00:00.000000Z]
        ],
        array_of_decimal32_attr: [
          Decimal.new("0.123456789"),
          Decimal.new("0.123456789"),
          Decimal.new("0.123456789")
        ],
        array_of_nullable_decimal32_attr: [
          nil,
          Decimal.new("0.123456789"),
          nil
        ],
        array_of_decimal64_attr: [
          Decimal.new("0.123456789123456789"),
          Decimal.new("0.123456789123456789"),
          Decimal.new("0.123456789123456789")
        ],
        array_of_nullable_decimal64_attr: [
          nil,
          nil,
          Decimal.new("0.123456789123456789")
        ],
        array_of_decimal128_attr: [
          Decimal.new("0.12345678912345678912345678912345678912", max_digits: 76),
          Decimal.new("0.12345678912345678912345678912345678912", max_digits: 76),
          Decimal.new("0.12345678912345678912345678912345678912", max_digits: 76)
        ],
        array_of_nullable_decimal128_attr: [
          Decimal.new("0.12345678912345678912345678912345678912", max_digits: 76),
          Decimal.new("0.12345678912345678912345678912345678912", max_digits: 76),
          nil
        ],
        array_of_json_attr: [%{"foo" => "bar"}, %{"baz" => "qux"}],
        array_of_nullable_json_attr: [%{"foo" => "bar"}, %{"baz" => "qux"}],
        array_of_map_attr: [
          %{"foo" => "value1", "bar" => "value2", "baz" => "value3"},
          %{"foo" => "value4", "bar" => "value5", "baz" => "value6"}
        ],
        array_of_ipv4_attr: ["192.168.1.1", "192.168.1.2", "192.168.1.3"],
        array_of_nullable_ipv4_attr: ["192.168.1.1", "192.168.1.2", nil],
        array_of_ipv6_attr: [
          "2001:0db8:85a3:0000:0000:8a2e:0370:7334",
          "2001:0db8:85a3:0000:0000:8a2e:0370:7335",
          "2001:0db8:85a3:0000:0000:8a2e:0370:7336"
        ],
        array_of_nullable_ipv6_attr: [
          nil,
          "2001:0db8:85a3:0000:0000:8a2e:0370:7335",
          "2001:0db8:85a3:0000:0000:8a2e:0370:7336"
        ],
        array_of_uuid_attr: [
          "550e8400-e29b-41d4-a716-446655440000",
          "550e8400-e29b-41d4-a716-446655440001",
          "550e8400-e29b-41d4-a716-446655440002"
        ],
        array_of_nullable_uuid_attr: [
          "550e8400-e29b-41d4-a716-446655440000",
          nil,
          "550e8400-e29b-41d4-a716-446655440002"
        ],
        array_of_decimal256_attr: [
          Decimal.new(
            "0.1234567891234567891234567891234567891234567891234567891234567891234567891234",
            max_digits: 76
          ),
          Decimal.new(
            "0.1234567891234567891234567891234567891234567891234567891234567891234567891234",
            max_digits: 76
          )
        ],
        array_of_nullable_decimal256_attr: [
          nil,
          Decimal.new(
            "0.1234567891234567891234567891234567891234567891234567891234567891234567891234",
            max_digits: 76
          )
        ],
        array_of_variant_attr: ["foo", 42],
        array_of_tuple_attr: [{"foo", 42, true}, {"bar", 43, false}, {"baz", 44, true}],
        array_of_point_attr: [{12.34, 56.78}, {12.34, 56.78}, {12.34, 56.78}],
        array_of_ring_attr: [
          [
            {1.0, 2.0},
            {3.0, 4.0},
            {5.0, 6.0}
          ],
          [
            {1.0, 2.0},
            {3.0, 4.0},
            {5.0, 6.0}
          ]
        ],
        array_of_polygon_attr: [
          [
            [
              {1.0, 2.0},
              {3.0, 4.0},
              {5.0, 6.0}
            ]
          ],
          [
            [
              {7.0, 8.0},
              {9.0, 10.0},
              {11.0, 12.0}
            ]
          ]
        ],
        array_of_multipolygon_attr: [
          [
            [
              [
                {1.0, 2.0},
                {3.0, 4.0},
                {5.0, 6.0}
              ]
            ]
          ],
          [
            [
              [
                {7.0, 8.0},
                {9.0, 10.0},
                {11.0, 12.0}
              ]
            ]
          ]
        ],
        enum8_attr: :enum8_min,
        enum16_attr: :enum16_max
      }

      assert {:ok,
              %AllTypes{
                string_attr: "Test String",
                nullable_string_attr: nil,
                low_cardinality_string_attr: "LowCard",
                low_cardinality_nullable_string_attr: nil,
                fixed_string_attr: "AAAAAAAAAAAAAAAA",
                nullable_fixed_string_attr: nil,
                int8_attr: 127,
                nullable_int8_attr: nil,
                int16_attr: 32_767,
                nullable_int16_attr: nil,
                int32_attr: 2_147_483_647,
                nullable_int32_attr: nil,
                int64_attr: 9_223_372_036_854_775_807,
                nullable_int64_attr: nil,
                int128_attr: 170_141_183_460_469_231_731_687_303_715_884_105_727,
                nullable_int128_attr: nil,
                int256_attr: 1,
                nullable_int256_attr: nil,
                uint8_attr: 255,
                nullable_uint8_attr: nil,
                uint16_attr: 65_535,
                nullable_uint16_attr: nil,
                uint32_attr: 4_294_967_295,
                nullable_uint32_attr: nil,
                uint64_attr: 18_446_744_073_709_551_615,
                nullable_uint64_attr: nil,
                uint128_attr: 340_282_366_920_938_463_463_374_607_431_768_211_455,
                nullable_uint128_attr: nil,
                uint256_attr: 1,
                nullable_uint256_attr: nil,
                float32_attr: 3.14,
                nullable_float32_attr: nil,
                float64_attr: 2.71828,
                nullable_float64_attr: nil,
                bool_attr: true,
                atom_attr: :some_atom,
                date_attr: ~D[2024-01-01],
                nullable_date_attr: nil,
                date32_attr: ~D[2024-01-01],
                datetime_attr: ~U[2024-01-01 12:00:00Z],
                datetime64_attr: ~U[2024-01-01 12:00:00.000000Z],
                decimal_attr: %Decimal{coef: 67, exp: -2, sign: 1},
                decimal32_attr: %Decimal{coef: 123_456_789, exp: -9, sign: 1},
                nullable_decimal32_attr: nil,
                decimal64_attr: %Decimal{coef: 123_456_789_123_456_789, exp: -18, sign: 1},
                nullable_decimal64_attr: nil,
                decimal128_attr: %Decimal{
                  coef: 12_345_678_912_345_678_912_345_678_912_345_678_912,
                  exp: -38,
                  sign: 1
                },
                nullable_decimal128_attr: nil,
                decimal256_attr: %Decimal{
                  coef:
                    1_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234,
                  exp: -76,
                  sign: 1
                },
                nullable_decimal256_attr: nil,
                json_attr: %{"foo" => "bar"},
                nullable_json_attr: nil,
                map_attr: %{"foo" => "value1", "bar" => "value2", "baz" => "value3"},
                point_attr: {12.34, 56.78},
                ring_attr: [
                  {1.0, 2.0},
                  {3.0, 4.0},
                  {5.0, 6.0}
                ],
                polygon_attr: [
                  [
                    {1.0, 2.0},
                    {3.0, 4.0},
                    {5.0, 6.0}
                  ]
                ],
                multipolygon_attr: [
                  [
                    [
                      {1.0, 2.0},
                      {3.0, 4.0},
                      {5.0, 6.0}
                    ]
                  ],
                  [
                    [
                      {7.0, 8.0},
                      {9.0, 10.0},
                      {11.0, 12.0}
                    ]
                  ]
                ],
                simple_agg_func_attr: 123,
                variant_attr: "string ou 42 ou true",
                array_of_string_attr: ["foo", "bar", "baz"],
                array_of_low_cardinality_string_attr: ["foo", "bar", "baz"],
                array_of_nullable_string_attr: ["foo", "bar", "baz"],
                array_of_low_cardinality_nullable_string_attr: ["foo", "bar", "baz"],
                array_of_int32_attr: [1, 2, 3],
                array_of_nullable_int32_attr: [1, 2, 3],
                array_of_int64_attr: [1, 2, 3],
                array_of_nullable_int64_attr: [1, 2, 3],
                array_of_uint32_attr: [1, 2, 3],
                array_of_nullable_uint32_attr: [1, 2, 3],
                array_of_uint64_attr: [1, 2, 3],
                array_of_nullable_uint64_attr: [1, 2, 3],
                array_of_float32_attr: [1.0, 2.0, 3.0],
                array_of_nullable_float32_attr: [1.0, 2.0, 3.0],
                array_of_float64_attr: [1.0, 2.0, 3.0],
                array_of_nullable_float64_attr: [1.0, 2.0, 3.0],
                array_of_bool_attr: [true, false, true],
                array_of_date_attr: [~D[2024-01-01], ~D[2024-01-02], ~D[2024-01-03]],
                array_of_nullable_date_attr: [~D[2024-01-01], ~D[2024-01-02], ~D[2024-01-03]],
                array_of_date32_attr: [~D[2024-01-01], ~D[2024-01-02], ~D[2024-01-03]],
                array_of_nullable_date32_attr: [~D[2024-01-01], ~D[2024-01-02], ~D[2024-01-03]],
                array_of_datetime_attr: [
                  ~U[2024-01-01 12:00:00Z],
                  ~U[2024-01-02 12:00:00Z],
                  ~U[2024-01-03 12:00:00Z]
                ],
                array_of_nullable_datetime_attr: [
                  ~U[2024-01-01 12:00:00Z],
                  ~U[2024-01-02 12:00:00Z],
                  ~U[2024-01-03 12:00:00Z]
                ],
                array_of_datetime64_attr: [
                  ~U[2024-01-01 12:00:00.000000Z],
                  ~U[2024-01-02 12:00:00.000000Z],
                  ~U[2024-01-03 12:00:00.000000Z]
                ],
                array_of_nullable_datetime64_attr: [
                  ~U[2024-01-01 12:00:00.000000Z],
                  ~U[2024-01-02 12:00:00.000000Z],
                  ~U[2024-01-03 12:00:00.000000Z]
                ],
                array_of_decimal32_attr: [
                  %Decimal{coef: 123_456_789, exp: -9, sign: 1},
                  %Decimal{coef: 123_456_789, exp: -9, sign: 1},
                  %Decimal{coef: 123_456_789, exp: -9, sign: 1}
                ],
                array_of_nullable_decimal32_attr: [
                  nil,
                  %Decimal{coef: 123_456_789, exp: -9, sign: 1},
                  nil
                ],
                array_of_decimal64_attr: [
                  %Decimal{coef: 123_456_789_123_456_789, exp: -18, sign: 1},
                  %Decimal{coef: 123_456_789_123_456_789, exp: -18, sign: 1},
                  %Decimal{coef: 123_456_789_123_456_789, exp: -18, sign: 1}
                ],
                array_of_nullable_decimal64_attr: [
                  nil,
                  nil,
                  %Decimal{coef: 123_456_789_123_456_789, exp: -18, sign: 1}
                ],
                array_of_decimal128_attr: [
                  %Decimal{
                    coef: 12_345_678_912_345_678_912_345_678_912_345_678_912,
                    exp: -38,
                    sign: 1
                  },
                  %Decimal{
                    coef: 12_345_678_912_345_678_912_345_678_912_345_678_912,
                    exp: -38,
                    sign: 1
                  },
                  %Decimal{
                    coef: 12_345_678_912_345_678_912_345_678_912_345_678_912,
                    exp: -38,
                    sign: 1
                  }
                ],
                array_of_nullable_decimal128_attr: [
                  %Decimal{
                    coef: 12_345_678_912_345_678_912_345_678_912_345_678_912,
                    exp: -38,
                    sign: 1
                  },
                  %Decimal{
                    coef: 12_345_678_912_345_678_912_345_678_912_345_678_912,
                    exp: -38,
                    sign: 1
                  },
                  nil
                ],
                array_of_json_attr: [%{"foo" => "bar"}, %{"baz" => "qux"}],
                array_of_nullable_json_attr: [%{"foo" => "bar"}, %{"baz" => "qux"}],
                array_of_map_attr: [
                  %{"foo" => "value1", "bar" => "value2", "baz" => "value3"},
                  %{"foo" => "value4", "bar" => "value5", "baz" => "value6"}
                ],
                array_of_ipv4_attr: [{192, 168, 1, 1}, {192, 168, 1, 2}, {192, 168, 1, 3}],
                array_of_nullable_ipv4_attr: [{192, 168, 1, 1}, {192, 168, 1, 2}, nil],
                array_of_ipv6_attr: [
                  {8193, 3512, 34211, 0, 0, 35374, 880, 29492},
                  {8193, 3512, 34211, 0, 0, 35374, 880, 29493},
                  {8193, 3512, 34211, 0, 0, 35374, 880, 29494}
                ],
                array_of_nullable_ipv6_attr: [
                  nil,
                  {8193, 3512, 34211, 0, 0, 35374, 880, 29493},
                  {8193, 3512, 34211, 0, 0, 35374, 880, 29494}
                ],
                array_of_uuid_attr: [
                  "550e8400-e29b-41d4-a716-446655440000",
                  "550e8400-e29b-41d4-a716-446655440001",
                  "550e8400-e29b-41d4-a716-446655440002"
                ],
                array_of_nullable_uuid_attr: [
                  "550e8400-e29b-41d4-a716-446655440000",
                  nil,
                  "550e8400-e29b-41d4-a716-446655440002"
                ],
                array_of_decimal256_attr: [
                  %Decimal{
                    coef:
                      1_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234,
                    exp: -76,
                    sign: 1
                  },
                  %Decimal{
                    coef:
                      1_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234,
                    exp: -76,
                    sign: 1
                  }
                ],
                array_of_nullable_decimal256_attr: [
                  nil,
                  %Decimal{
                    coef:
                      1_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234,
                    exp: -76,
                    sign: 1
                  }
                ],
                array_of_variant_attr: ["foo", 42],
                array_of_tuple_attr: [{"foo", 42, true}, {"bar", 43, false}, {"baz", 44, true}],
                array_of_point_attr: [{12.34, 56.78}, {12.34, 56.78}, {12.34, 56.78}],
                array_of_ring_attr: [
                  [
                    {1.0, 2.0},
                    {3.0, 4.0},
                    {5.0, 6.0}
                  ],
                  [
                    {1.0, 2.0},
                    {3.0, 4.0},
                    {5.0, 6.0}
                  ]
                ],
                array_of_polygon_attr: [
                  [
                    [
                      {1.0, 2.0},
                      {3.0, 4.0},
                      {5.0, 6.0}
                    ]
                  ],
                  [
                    [
                      {7.0, 8.0},
                      {9.0, 10.0},
                      {11.0, 12.0}
                    ]
                  ]
                ],
                array_of_multipolygon_attr: [
                  [
                    [
                      [
                        {1.0, 2.0},
                        {3.0, 4.0},
                        {5.0, 6.0}
                      ]
                    ]
                  ],
                  [
                    [
                      [
                        {7.0, 8.0},
                        {9.0, 10.0},
                        {11.0, 12.0}
                      ]
                    ]
                  ]
                ],
                enum8_attr: :enum8_min,
                enum16_attr: :enum16_max
              }} =
               AllTypes
               |> Ash.Changeset.for_create(:create, params)
               |> Ash.create()

      assert [
               %AllTypes{
                 string_attr: "Test String",
                 nullable_string_attr: nil,
                 low_cardinality_string_attr: "LowCard",
                 low_cardinality_nullable_string_attr: nil,
                 fixed_string_attr: "AAAAAAAAAAAAAAAA",
                 nullable_fixed_string_attr: nil,
                 int8_attr: 127,
                 nullable_int8_attr: nil,
                 int16_attr: 32_767,
                 nullable_int16_attr: nil,
                 int32_attr: 2_147_483_647,
                 nullable_int32_attr: nil,
                 int64_attr: 9_223_372_036_854_775_807,
                 nullable_int64_attr: nil,
                 int128_attr: 170_141_183_460_469_231_731_687_303_715_884_105_727,
                 nullable_int128_attr: nil,
                 int256_attr: 1,
                 nullable_int256_attr: nil,
                 uint8_attr: 255,
                 nullable_uint8_attr: nil,
                 uint16_attr: 65_535,
                 nullable_uint16_attr: nil,
                 uint32_attr: 4_294_967_295,
                 nullable_uint32_attr: nil,
                 uint64_attr: 18_446_744_073_709_551_615,
                 nullable_uint64_attr: nil,
                 uint128_attr: 340_282_366_920_938_463_463_374_607_431_768_211_455,
                 nullable_uint128_attr: nil,
                 uint256_attr: 1,
                 nullable_uint256_attr: nil,
                 float32_attr: 3.140000104904175,
                 nullable_float32_attr: nil,
                 float64_attr: 2.71828,
                 nullable_float64_attr: nil,
                 bool_attr: true,
                 atom_attr: :some_atom,
                 date_attr: ~D[2024-01-01],
                 nullable_date_attr: nil,
                 date32_attr: ~D[2024-01-01],
                 datetime_attr: ~U[2024-01-01 12:00:00Z],
                 datetime64_attr: ~U[2024-01-01 12:00:00.000000Z],
                 decimal_attr: %Decimal{coef: 67, exp: -2, sign: 1},
                 decimal32_attr: %Decimal{coef: 123_456_789, exp: -9, sign: 1},
                 nullable_decimal32_attr: nil,
                 decimal64_attr: %Decimal{coef: 123_456_789_123_456_789, exp: -18, sign: 1},
                 nullable_decimal64_attr: nil,
                 decimal128_attr: %Decimal{
                   coef: 12_345_678_912_345_678_912_345_678_912_345_678_912,
                   exp: -38,
                   sign: 1
                 },
                 nullable_decimal128_attr: nil,
                 decimal256_attr: %Decimal{
                   coef:
                     1_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234,
                   exp: -76,
                   sign: 1
                 },
                 nullable_decimal256_attr: nil,
                 json_attr: %{"foo" => "bar"},
                 nullable_json_attr: nil,
                 map_attr: %{"foo" => "value1", "bar" => "value2", "baz" => "value3"},
                 point_attr: {12.34, 56.78},
                 ring_attr: [
                   {1.0, 2.0},
                   {3.0, 4.0},
                   {5.0, 6.0}
                 ],
                 polygon_attr: [
                   [
                     {1.0, 2.0},
                     {3.0, 4.0},
                     {5.0, 6.0}
                   ]
                 ],
                 multipolygon_attr: [
                   [
                     [
                       {1.0, 2.0},
                       {3.0, 4.0},
                       {5.0, 6.0}
                     ]
                   ],
                   [
                     [
                       {7.0, 8.0},
                       {9.0, 10.0},
                       {11.0, 12.0}
                     ]
                   ]
                 ],
                 simple_agg_func_attr: 123,
                 variant_attr: "string ou 42 ou true",
                 array_of_string_attr: ["foo", "bar", "baz"],
                 array_of_low_cardinality_string_attr: ["foo", "bar", "baz"],
                 array_of_nullable_string_attr: ["foo", "bar", "baz"],
                 array_of_low_cardinality_nullable_string_attr: ["foo", "bar", "baz"],
                 array_of_int32_attr: [1, 2, 3],
                 array_of_nullable_int32_attr: [1, 2, 3],
                 array_of_int64_attr: [1, 2, 3],
                 array_of_nullable_int64_attr: [1, 2, 3],
                 array_of_uint32_attr: [1, 2, 3],
                 array_of_nullable_uint32_attr: [1, 2, 3],
                 array_of_uint64_attr: [1, 2, 3],
                 array_of_nullable_uint64_attr: [1, 2, 3],
                 array_of_float32_attr: [1.0, 2.0, 3.0],
                 array_of_nullable_float32_attr: [1.0, 2.0, 3.0],
                 array_of_float64_attr: [1.0, 2.0, 3.0],
                 array_of_nullable_float64_attr: [1.0, 2.0, 3.0],
                 array_of_bool_attr: [true, false, true],
                 array_of_date_attr: [~D[2024-01-01], ~D[2024-01-02], ~D[2024-01-03]],
                 array_of_nullable_date_attr: [~D[2024-01-01], ~D[2024-01-02], ~D[2024-01-03]],
                 array_of_date32_attr: [~D[2024-01-01], ~D[2024-01-02], ~D[2024-01-03]],
                 array_of_nullable_date32_attr: [~D[2024-01-01], ~D[2024-01-02], ~D[2024-01-03]],
                 array_of_datetime_attr: [
                   ~U[2024-01-01 12:00:00Z],
                   ~U[2024-01-02 12:00:00Z],
                   ~U[2024-01-03 12:00:00Z]
                 ],
                 array_of_nullable_datetime_attr: [
                   ~U[2024-01-01 12:00:00Z],
                   ~U[2024-01-02 12:00:00Z],
                   ~U[2024-01-03 12:00:00Z]
                 ],
                 array_of_datetime64_attr: [
                   ~U[2024-01-01 12:00:00.000000Z],
                   ~U[2024-01-02 12:00:00.000000Z],
                   ~U[2024-01-03 12:00:00.000000Z]
                 ],
                 array_of_nullable_datetime64_attr: [
                   ~U[2024-01-01 12:00:00.000000Z],
                   ~U[2024-01-02 12:00:00.000000Z],
                   ~U[2024-01-03 12:00:00.000000Z]
                 ],
                 array_of_decimal32_attr: [
                   %Decimal{coef: 123_456_789, exp: -9, sign: 1},
                   %Decimal{coef: 123_456_789, exp: -9, sign: 1},
                   %Decimal{coef: 123_456_789, exp: -9, sign: 1}
                 ],
                 array_of_nullable_decimal32_attr: [
                   nil,
                   %Decimal{coef: 123_456_789, exp: -9, sign: 1},
                   nil
                 ],
                 array_of_decimal64_attr: [
                   %Decimal{coef: 123_456_789_123_456_789, exp: -18, sign: 1},
                   %Decimal{coef: 123_456_789_123_456_789, exp: -18, sign: 1},
                   %Decimal{coef: 123_456_789_123_456_789, exp: -18, sign: 1}
                 ],
                 array_of_nullable_decimal64_attr: [
                   nil,
                   nil,
                   %Decimal{coef: 123_456_789_123_456_789, exp: -18, sign: 1}
                 ],
                 array_of_decimal128_attr: [
                   %Decimal{
                     coef: 12_345_678_912_345_678_912_345_678_912_345_678_912,
                     exp: -38,
                     sign: 1
                   },
                   %Decimal{
                     coef: 12_345_678_912_345_678_912_345_678_912_345_678_912,
                     exp: -38,
                     sign: 1
                   },
                   %Decimal{
                     coef: 12_345_678_912_345_678_912_345_678_912_345_678_912,
                     exp: -38,
                     sign: 1
                   }
                 ],
                 array_of_nullable_decimal128_attr: [
                   %Decimal{
                     coef: 12_345_678_912_345_678_912_345_678_912_345_678_912,
                     exp: -38,
                     sign: 1
                   },
                   %Decimal{
                     coef: 12_345_678_912_345_678_912_345_678_912_345_678_912,
                     exp: -38,
                     sign: 1
                   },
                   nil
                 ],
                 array_of_json_attr: [%{"foo" => "bar"}, %{"baz" => "qux"}],
                 array_of_nullable_json_attr: [%{"foo" => "bar"}, %{"baz" => "qux"}],
                 array_of_map_attr: [
                   %{"foo" => "value1", "bar" => "value2", "baz" => "value3"},
                   %{"foo" => "value4", "bar" => "value5", "baz" => "value6"}
                 ],
                 array_of_ipv4_attr: [{192, 168, 1, 1}, {192, 168, 1, 2}, {192, 168, 1, 3}],
                 array_of_nullable_ipv4_attr: [{192, 168, 1, 1}, {192, 168, 1, 2}, nil],
                 array_of_ipv6_attr: [
                   {8193, 3512, 34211, 0, 0, 35374, 880, 29492},
                   {8193, 3512, 34211, 0, 0, 35374, 880, 29493},
                   {8193, 3512, 34211, 0, 0, 35374, 880, 29494}
                 ],
                 array_of_nullable_ipv6_attr: [
                   nil,
                   {8193, 3512, 34211, 0, 0, 35374, 880, 29493},
                   {8193, 3512, 34211, 0, 0, 35374, 880, 29494}
                 ],
                 array_of_uuid_attr: [
                   "550e8400-e29b-41d4-a716-446655440000",
                   "550e8400-e29b-41d4-a716-446655440001",
                   "550e8400-e29b-41d4-a716-446655440002"
                 ],
                 array_of_nullable_uuid_attr: [
                   "550e8400-e29b-41d4-a716-446655440000",
                   nil,
                   "550e8400-e29b-41d4-a716-446655440002"
                 ],
                 array_of_decimal256_attr: [
                   %Decimal{
                     coef:
                       1_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234,
                     exp: -76,
                     sign: 1
                   },
                   %Decimal{
                     coef:
                       1_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234,
                     exp: -76,
                     sign: 1
                   }
                 ],
                 array_of_nullable_decimal256_attr: [
                   nil,
                   %Decimal{
                     coef:
                       1_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234_567_891_234,
                     exp: -76,
                     sign: 1
                   }
                 ],
                 array_of_variant_attr: ["foo", 42],
                 array_of_tuple_attr: [{"foo", 42, true}, {"bar", 43, false}, {"baz", 44, true}],
                 array_of_point_attr: [{12.34, 56.78}, {12.34, 56.78}, {12.34, 56.78}],
                 array_of_ring_attr: [
                   [
                     {1.0, 2.0},
                     {3.0, 4.0},
                     {5.0, 6.0}
                   ],
                   [
                     {1.0, 2.0},
                     {3.0, 4.0},
                     {5.0, 6.0}
                   ]
                 ],
                 array_of_polygon_attr: [
                   [
                     [
                       {1.0, 2.0},
                       {3.0, 4.0},
                       {5.0, 6.0}
                     ]
                   ],
                   [
                     [
                       {7.0, 8.0},
                       {9.0, 10.0},
                       {11.0, 12.0}
                     ]
                   ]
                 ],
                 array_of_multipolygon_attr: [
                   [
                     [
                       [
                         {1.0, 2.0},
                         {3.0, 4.0},
                         {5.0, 6.0}
                       ]
                     ]
                   ],
                   [
                     [
                       [
                         {7.0, 8.0},
                         {9.0, 10.0},
                         {11.0, 12.0}
                       ]
                     ]
                   ]
                 ],
                 enum8_attr: :enum8_min,
                 enum16_attr: :enum16_max
               }
             ] =
               AllTypes
               |> Ash.Query.filter(string_attr == "Test String")
               |> Ash.read!()
    end

    @tag timeout: 100_000
    test "creates insert with nullable fields having actual values" do
      params = %{
        string_attr: "Nullable Fields Test",
        nullable_string_attr: "Not nil",
        low_cardinality_string_attr: "LowCard",
        low_cardinality_nullable_string_attr: "NotNullLowCard",
        fixed_string_attr: String.duplicate("B", 16),
        nullable_fixed_string_attr: String.duplicate("C", 16),
        int8_attr: -128,
        nullable_int8_attr: 42,
        int16_attr: -32_768,
        nullable_int16_attr: 100,
        int32_attr: -2_147_483_648,
        nullable_int32_attr: 2_147_483_647,
        int64_attr: -9_223_372_036_854_775_808,
        nullable_int64_attr: 9_223_372_036_854_775_807,
        int128_attr: 1,
        nullable_int128_attr: 170_141_183_460_469_231_731_687_303_715_884_105_727,
        int256_attr: 1,
        nullable_int256_attr: 2,
        uint8_attr: 0,
        nullable_uint8_attr: 255,
        uint16_attr: 0,
        nullable_uint16_attr: 65_535,
        uint32_attr: 0,
        nullable_uint32_attr: 4_294_967_295,
        uint64_attr: 0,
        nullable_uint64_attr: 18_446_744_073_709_551_615,
        uint128_attr: 0,
        nullable_uint128_attr: 340_282_366_920_938_463_463_374_607_431_768_211_455,
        uint256_attr: 1,
        nullable_uint256_attr: 2,
        float32_attr: 1.0,
        nullable_float32_attr: 2.5,
        float64_attr: 1.0,
        nullable_float64_attr: 3.14159,
        bool_attr: false,
        atom_attr: :some_atom,
        date_attr: ~D[2024-06-15],
        nullable_date_attr: ~D[2024-12-31],
        date32_attr: ~D[2024-06-15],
        datetime_attr: ~U[2024-06-15 08:00:00Z],
        datetime64_attr: ~U[2024-06-15 08:00:00.123456Z],
        decimal_attr: Decimal.new("99.99"),
        decimal32_attr: Decimal.new("1.0"),
        nullable_decimal32_attr: Decimal.new("2.0"),
        decimal64_attr: Decimal.new("1.0"),
        nullable_decimal64_attr: Decimal.new("3.0"),
        decimal128_attr: Decimal.new("0.12345678912345678912345678912345678912", max_digits: 76),
        nullable_decimal128_attr:
          Decimal.new("0.12345678912345678912345678912345678912", max_digits: 76),
        decimal256_attr:
          Decimal.new(
            "0.1234567891234567891234567891234567891234567891234567891234567891234567891234",
            max_digits: 76
          ),
        nullable_decimal256_attr:
          Decimal.new(
            "0.1234567891234567891234567891234567891234567891234567891234567891234567891234",
            max_digits: 76
          ),
        json_attr: %{"key" => "value"},
        nullable_json_attr: %{"nested" => %{"a" => 1}},
        map_attr: %{"foo" => "a", "bar" => "b", "baz" => "c"},
        ipv4_attr: "10.0.0.1",
        nullable_ipv4_attr: "172.16.0.1",
        ipv6_attr: "::1",
        nullable_ipv6_attr: "fe80::1",
        uuid_attr: "550e8400-e29b-41d4-a716-446655440000",
        nullable_uuid_attr: "550e8400-e29b-41d4-a716-446655440001",
        tuple_attr: {"hello", 99, false},
        point_attr: {0.0, 0.0},
        ring_attr: [{0.0, 0.0}, {1.0, 0.0}, {0.0, 1.0}],
        polygon_attr: [[{0.0, 0.0}, {1.0, 0.0}, {0.0, 1.0}]],
        multipolygon_attr: [[[{0.0, 0.0}, {1.0, 0.0}, {0.0, 1.0}]]],
        simple_agg_func_attr: 0,
        variant_attr: 42,
        array_of_string_attr: ["a"],
        array_of_low_cardinality_string_attr: ["a"],
        array_of_nullable_string_attr: ["b"],
        array_of_low_cardinality_nullable_string_attr: ["c"],
        array_of_int32_attr: [0],
        array_of_nullable_int32_attr: [1],
        array_of_int64_attr: [0],
        array_of_nullable_int64_attr: [2],
        array_of_uint32_attr: [0],
        array_of_nullable_uint32_attr: [3],
        array_of_uint64_attr: [0],
        array_of_nullable_uint64_attr: [4],
        array_of_float32_attr: [0.0],
        array_of_nullable_float32_attr: [1.5],
        array_of_float64_attr: [0.0],
        array_of_nullable_float64_attr: [2.5],
        array_of_bool_attr: [false],
        array_of_date_attr: [~D[2024-01-01]],
        array_of_nullable_date_attr: [~D[2024-06-15]],
        array_of_date32_attr: [~D[2024-01-01]],
        array_of_nullable_date32_attr: [~D[2024-06-15]],
        array_of_datetime_attr: [~U[2024-01-01 00:00:00Z]],
        array_of_nullable_datetime_attr: [~U[2024-06-15 00:00:00Z]],
        array_of_datetime64_attr: [~U[2024-01-01 00:00:00.000000Z]],
        array_of_nullable_datetime64_attr: [~U[2024-06-15 00:00:00.000000Z]],
        array_of_decimal32_attr: [Decimal.new("1.0")],
        array_of_nullable_decimal32_attr: [nil],
        array_of_decimal64_attr: [Decimal.new("1.0")],
        array_of_nullable_decimal64_attr: [nil],
        array_of_decimal128_attr: [
          Decimal.new("0.12345678912345678912345678912345678912", max_digits: 76)
        ],
        array_of_nullable_decimal128_attr: [nil],
        array_of_decimal256_attr: [
          Decimal.new(
            "0.1234567891234567891234567891234567891234567891234567891234567891234567891234",
            max_digits: 76
          )
        ],
        array_of_nullable_decimal256_attr: [nil],
        array_of_json_attr: [%{"x" => 1}],
        array_of_nullable_json_attr: [nil],
        array_of_map_attr: [%{"foo" => "v", "bar" => "v", "baz" => "v"}],
        array_of_ipv4_attr: ["10.0.0.1"],
        array_of_nullable_ipv4_attr: [nil],
        array_of_ipv6_attr: ["::1"],
        array_of_nullable_ipv6_attr: [nil],
        array_of_uuid_attr: ["550e8400-e29b-41d4-a716-446655440000"],
        array_of_nullable_uuid_attr: [nil],
        array_of_variant_attr: ["hello"],
        array_of_tuple_attr: [{"x", 1, true}],
        array_of_point_attr: [{0.0, 0.0}],
        array_of_ring_attr: [[{0.0, 0.0}, {1.0, 0.0}, {0.0, 1.0}]],
        array_of_polygon_attr: [[[{0.0, 0.0}, {1.0, 0.0}, {0.0, 1.0}]]],
        array_of_multipolygon_attr: [[[[{0.0, 0.0}, {1.0, 0.0}, {0.0, 1.0}]]]],
        enum8_attr: :enum8_zero,
        enum16_attr: :enum16_zero
      }

      assert {:ok,
              %AllTypes{
                string_attr: "Nullable Fields Test",
                nullable_string_attr: "Not nil",
                nullable_fixed_string_attr: "CCCCCCCCCCCCCCCC",
                nullable_int8_attr: 42,
                nullable_uint8_attr: 255,
                nullable_float32_attr: _,
                nullable_float64_attr: 3.14159,
                nullable_date_attr: ~D[2024-12-31],
                nullable_uuid_attr: "550e8400-e29b-41d4-a716-446655440001",
                nullable_ipv4_attr: _,
                nullable_json_attr: %{"nested" => %{"a" => 1}},
                bool_attr: false,
                enum8_attr: :enum8_zero,
                enum16_attr: :enum16_zero
              }} =
               AllTypes
               |> Ash.Changeset.for_create(:create, params)
               |> Ash.create()
    end

    @tag timeout: 100_000
    test "creates insert with enum boundary values" do
      for {e8, e16} <- [
            {:enum8_min, :enum16_min},
            {:enum8_zero, :enum16_zero},
            {:enum8_max, :enum16_max}
          ] do
        params = %{
          string_attr: "Enum Test #{e8} #{e16}",
          low_cardinality_string_attr: "x",
          fixed_string_attr: String.duplicate("C", 16),
          nullable_fixed_string_attr: nil,
          int8_attr: 0,
          int16_attr: 0,
          int32_attr: 0,
          int64_attr: 0,
          int128_attr: 0,
          int256_attr: 0,
          uint8_attr: 0,
          uint16_attr: 0,
          uint32_attr: 0,
          uint64_attr: 0,
          uint128_attr: 0,
          uint256_attr: 0,
          float32_attr: 0.0,
          float64_attr: 0.0,
          bool_attr: true,
          atom_attr: :x,
          date_attr: ~D[2024-01-01],
          date32_attr: ~D[2024-01-01],
          datetime_attr: ~U[2024-01-01 00:00:00Z],
          datetime64_attr: ~U[2024-01-01 00:00:00.000000Z],
          decimal_attr: Decimal.new("0.01"),
          decimal32_attr: Decimal.new("0.1"),
          decimal64_attr: Decimal.new("0.1"),
          decimal128_attr:
            Decimal.new("0.12345678912345678912345678912345678912", max_digits: 76),
          decimal256_attr:
            Decimal.new(
              "0.1234567891234567891234567891234567891234567891234567891234567891234567891234",
              max_digits: 76
            ),
          json_attr: %{},
          map_attr: %{"foo" => "a", "bar" => "b", "baz" => "c"},
          ipv4_attr: "127.0.0.1",
          ipv6_attr: "::1",
          uuid_attr: "550e8400-e29b-41d4-a716-446655440000",
          tuple_attr: {"a", 1, true},
          point_attr: {0.0, 0.0},
          ring_attr: [{0.0, 0.0}, {1.0, 0.0}, {0.0, 1.0}],
          polygon_attr: [[{0.0, 0.0}, {1.0, 0.0}, {0.0, 1.0}]],
          multipolygon_attr: [[[{0.0, 0.0}, {1.0, 0.0}, {0.0, 1.0}]]],
          simple_agg_func_attr: 0,
          variant_attr: "v",
          array_of_string_attr: [],
          array_of_low_cardinality_string_attr: [],
          array_of_nullable_string_attr: [],
          array_of_low_cardinality_nullable_string_attr: [],
          array_of_int32_attr: [],
          array_of_nullable_int32_attr: [],
          array_of_int64_attr: [],
          array_of_nullable_int64_attr: [],
          array_of_uint32_attr: [],
          array_of_nullable_uint32_attr: [],
          array_of_uint64_attr: [],
          array_of_nullable_uint64_attr: [],
          array_of_float32_attr: [],
          array_of_nullable_float32_attr: [],
          array_of_float64_attr: [],
          array_of_nullable_float64_attr: [],
          array_of_bool_attr: [],
          array_of_date_attr: [],
          array_of_nullable_date_attr: [],
          array_of_date32_attr: [],
          array_of_nullable_date32_attr: [],
          array_of_datetime_attr: [],
          array_of_nullable_datetime_attr: [],
          array_of_datetime64_attr: [],
          array_of_nullable_datetime64_attr: [],
          array_of_decimal32_attr: [],
          array_of_nullable_decimal32_attr: [],
          array_of_decimal64_attr: [],
          array_of_nullable_decimal64_attr: [],
          array_of_decimal128_attr: [],
          array_of_nullable_decimal128_attr: [],
          array_of_decimal256_attr: [],
          array_of_nullable_decimal256_attr: [],
          array_of_json_attr: [],
          array_of_nullable_json_attr: [],
          array_of_map_attr: [],
          array_of_ipv4_attr: [],
          array_of_nullable_ipv4_attr: [],
          array_of_ipv6_attr: [],
          array_of_nullable_ipv6_attr: [],
          array_of_uuid_attr: [],
          array_of_nullable_uuid_attr: [],
          array_of_variant_attr: [],
          array_of_tuple_attr: [],
          array_of_point_attr: [],
          array_of_ring_attr: [],
          array_of_polygon_attr: [],
          array_of_multipolygon_attr: [],
          enum8_attr: e8,
          enum16_attr: e16
        }

        assert {:ok, %AllTypes{enum8_attr: ^e8, enum16_attr: ^e16}} =
                 AllTypes
                 |> Ash.Changeset.for_create(:create, params)
                 |> Ash.create()
      end
    end
  end
end
