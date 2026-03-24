defmodule PhoenixKitEntities.FormBuilderValidationTest do
  use ExUnit.Case

  alias PhoenixKitEntities.FormBuilder

  # FormBuilder.validate_data/3 is a pure function that validates data params
  # against an entity's field definitions. No DB needed.

  defp entity(fields) do
    %PhoenixKitEntities{fields_definition: fields}
  end

  describe "validate_data/2 with text fields" do
    test "valid text value" do
      entity = entity([%{"type" => "text", "key" => "name", "label" => "Name"}])
      assert {:ok, %{"name" => "hello"}} = FormBuilder.validate_data(entity, %{"name" => "hello"})
    end

    test "nil text value is accepted when not required" do
      entity = entity([%{"type" => "text", "key" => "name", "label" => "Name"}])
      assert {:ok, %{"name" => nil}} = FormBuilder.validate_data(entity, %{"name" => nil})
    end

    test "required text field rejects nil" do
      entity =
        entity([%{"type" => "text", "key" => "name", "label" => "Name", "required" => true}])

      assert {:error, errors} = FormBuilder.validate_data(entity, %{"name" => nil})
      assert Map.has_key?(errors, "name")
    end

    test "required text field rejects empty string" do
      entity =
        entity([%{"type" => "text", "key" => "name", "label" => "Name", "required" => true}])

      assert {:error, errors} = FormBuilder.validate_data(entity, %{"name" => ""})
      assert Map.has_key?(errors, "name")
    end
  end

  describe "validate_data/2 with email fields" do
    test "valid email" do
      entity = entity([%{"type" => "email", "key" => "email", "label" => "Email"}])

      assert {:ok, %{"email" => "test@example.com"}} =
               FormBuilder.validate_data(entity, %{"email" => "test@example.com"})
    end

    test "invalid email without @" do
      entity = entity([%{"type" => "email", "key" => "email", "label" => "Email"}])
      assert {:error, errors} = FormBuilder.validate_data(entity, %{"email" => "invalid"})
      assert Map.has_key?(errors, "email")
    end

    test "empty email is accepted when not required" do
      entity = entity([%{"type" => "email", "key" => "email", "label" => "Email"}])
      assert {:ok, _} = FormBuilder.validate_data(entity, %{"email" => ""})
    end
  end

  describe "validate_data/2 with url fields" do
    test "valid url with protocol" do
      entity = entity([%{"type" => "url", "key" => "site", "label" => "Site"}])

      assert {:ok, %{"site" => "https://example.com"}} =
               FormBuilder.validate_data(entity, %{"site" => "https://example.com"})
    end

    test "url without protocol gets https prepended" do
      entity = entity([%{"type" => "url", "key" => "site", "label" => "Site"}])

      assert {:ok, %{"site" => "https://example.com"}} =
               FormBuilder.validate_data(entity, %{"site" => "example.com"})
    end

    test "http url is preserved" do
      entity = entity([%{"type" => "url", "key" => "site", "label" => "Site"}])

      assert {:ok, %{"site" => "http://example.com"}} =
               FormBuilder.validate_data(entity, %{"site" => "http://example.com"})
    end
  end

  describe "validate_data/2 with number fields" do
    test "valid integer string" do
      entity = entity([%{"type" => "number", "key" => "qty", "label" => "Qty"}])
      assert {:ok, %{"qty" => 5.0}} = FormBuilder.validate_data(entity, %{"qty" => "5"})
    end

    test "valid float string" do
      entity = entity([%{"type" => "number", "key" => "price", "label" => "Price"}])
      assert {:ok, %{"price" => 9.99}} = FormBuilder.validate_data(entity, %{"price" => "9.99"})
    end

    test "invalid number string" do
      entity = entity([%{"type" => "number", "key" => "qty", "label" => "Qty"}])
      assert {:error, errors} = FormBuilder.validate_data(entity, %{"qty" => "abc"})
      assert Map.has_key?(errors, "qty")
    end

    test "empty number is accepted when not required" do
      entity = entity([%{"type" => "number", "key" => "qty", "label" => "Qty"}])
      assert {:ok, _} = FormBuilder.validate_data(entity, %{"qty" => ""})
    end
  end

  describe "validate_data/2 with boolean fields" do
    test "true values" do
      entity = entity([%{"type" => "boolean", "key" => "active", "label" => "Active"}])

      for val <- [true, "true", "1", 1] do
        assert {:ok, %{"active" => true}} = FormBuilder.validate_data(entity, %{"active" => val})
      end
    end

    test "false values" do
      entity = entity([%{"type" => "boolean", "key" => "active", "label" => "Active"}])

      for val <- [false, "false", "0", 0, nil, ""] do
        assert {:ok, %{"active" => false}} = FormBuilder.validate_data(entity, %{"active" => val})
      end
    end
  end

  describe "validate_data/2 with select fields" do
    test "valid option" do
      entity =
        entity([
          %{
            "type" => "select",
            "key" => "cat",
            "label" => "Category",
            "options" => ["A", "B", "C"]
          }
        ])

      assert {:ok, %{"cat" => "B"}} = FormBuilder.validate_data(entity, %{"cat" => "B"})
    end

    test "invalid option" do
      entity =
        entity([
          %{"type" => "select", "key" => "cat", "label" => "Category", "options" => ["A", "B"]}
        ])

      assert {:error, errors} = FormBuilder.validate_data(entity, %{"cat" => "Z"})
      assert Map.has_key?(errors, "cat")
    end

    test "nil is accepted for optional select" do
      entity =
        entity([
          %{"type" => "select", "key" => "cat", "label" => "Category", "options" => ["A", "B"]}
        ])

      assert {:ok, %{"cat" => nil}} = FormBuilder.validate_data(entity, %{"cat" => nil})
    end

    test "empty string is accepted for optional select" do
      entity =
        entity([
          %{"type" => "select", "key" => "cat", "label" => "Category", "options" => ["A", "B"]}
        ])

      assert {:ok, %{"cat" => nil}} = FormBuilder.validate_data(entity, %{"cat" => ""})
    end
  end

  describe "validate_data/2 with radio fields" do
    test "valid option" do
      entity =
        entity([
          %{
            "type" => "radio",
            "key" => "priority",
            "label" => "Priority",
            "options" => ["Low", "High"]
          }
        ])

      assert {:ok, %{"priority" => "Low"}} =
               FormBuilder.validate_data(entity, %{"priority" => "Low"})
    end

    test "invalid option" do
      entity =
        entity([
          %{
            "type" => "radio",
            "key" => "priority",
            "label" => "Priority",
            "options" => ["Low", "High"]
          }
        ])

      assert {:error, errors} = FormBuilder.validate_data(entity, %{"priority" => "Medium"})
      assert Map.has_key?(errors, "priority")
    end
  end

  describe "validate_data/2 with multiple fields" do
    test "validates all fields together" do
      entity =
        entity([
          %{"type" => "text", "key" => "name", "label" => "Name", "required" => true},
          %{"type" => "number", "key" => "price", "label" => "Price"},
          %{"type" => "boolean", "key" => "active", "label" => "Active"}
        ])

      assert {:ok, data} =
               FormBuilder.validate_data(entity, %{
                 "name" => "Widget",
                 "price" => "19.99",
                 "active" => "true"
               })

      assert data["name"] == "Widget"
      assert data["price"] == 19.99
      assert data["active"] == true
    end

    test "returns all errors at once" do
      entity =
        entity([
          %{"type" => "text", "key" => "name", "label" => "Name", "required" => true},
          %{"type" => "number", "key" => "price", "label" => "Price"},
          %{"type" => "email", "key" => "email", "label" => "Email"}
        ])

      assert {:error, errors} =
               FormBuilder.validate_data(entity, %{
                 "name" => "",
                 "price" => "not-a-number",
                 "email" => "invalid"
               })

      assert Map.has_key?(errors, "name")
      assert Map.has_key?(errors, "price")
      assert Map.has_key?(errors, "email")
    end
  end

  describe "validate_data/2 with missing fields in params" do
    test "missing optional field gets nil" do
      entity = entity([%{"type" => "text", "key" => "name", "label" => "Name"}])
      assert {:ok, %{"name" => nil}} = FormBuilder.validate_data(entity, %{})
    end

    test "missing required field fails" do
      entity =
        entity([%{"type" => "text", "key" => "name", "label" => "Name", "required" => true}])

      assert {:error, errors} = FormBuilder.validate_data(entity, %{})
      assert Map.has_key?(errors, "name")
    end
  end

  describe "validate_data/2 with empty entity" do
    test "no fields means no validation needed" do
      entity = entity([])
      assert {:ok, %{}} = FormBuilder.validate_data(entity, %{"extra" => "data"})
    end

    test "nil fields_definition treated as empty" do
      entity = %PhoenixKitEntities{fields_definition: nil}
      assert {:ok, %{}} = FormBuilder.validate_data(entity, %{})
    end
  end
end
