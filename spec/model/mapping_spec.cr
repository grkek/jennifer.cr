require "../spec_helper"

postgres_only do
  class ContactWithArray < ApplicationRecord
    mapping({
      id: Primary32,
      tags: Array(Int32)
    })
  end
end

module Mapping11
  include Jennifer::Macros
  include Jennifer::Model::Mapping

  mapping(
    id: Primary32
  )
end

module Mapping12
  include Jennifer::Macros
  include Jennifer::Model::Mapping

  mapping(
    name: String?
  )
end

module CompositeMapping
  include Mapping11
  include Mapping12

  mapping(
    password_digest: String?
  )
end

module ModuleWithoutMapping
  include CompositeMapping
end

class UserWithModuleMapping < Jennifer::Model::Base
  include ModuleWithoutMapping

  table_name "users"

  mapping(
    email: String?
  )
end

describe Jennifer::Model::Mapping do
  select_regexp = /[\S\s]*SELECT contacts\.\*/i

  describe "#reload" do
    it "assign all values from db to existing object" do
      c1 = Factory.create_contact
      c2 = Contact.all.first!
      c1.age = 55
      c1.save!
      c2.reload
      c2.age.should eq(55)
    end

    it "raises exception with errors if invalid on save!" do
      contact = Factory.create_contact
      contact.age = 12
      contact.name = "much too long for name"
      contact.description = "much too long for description"
      begin
        contact.save!
        fail("should raise validation exception")
      rescue ex : Jennifer::RecordInvalid
        contact.errors.size.should eq(3)
        raw_errors = contact.errors
        raw_errors[:age].should eq(["is not included in the list"])
        raw_errors[:name].should eq(["is too long (maximum is 15 characters)"])
        raw_errors[:description].should eq(["Too large description"])
      end
    end
  end

  describe "#attribute_metadata" do
    describe "with symbol argument" do
      it do
        Factory.build_contact.attribute_metadata(:id)
          .should eq({type: Int32, primary: true, parsed_type: "Int32?", column: "id", auto: true})
        Factory.build_contact.attribute_metadata(:name)
          .should eq({type: String, parsed_type: "String", column: "name"})
        Factory.build_address.attribute_metadata(:street)
          .should eq({type: String, parsed_type: "String", column: "street"})
      end
    end

    describe "with string argument" do
      it do
        Factory.build_contact.attribute_metadata("id")
          .should eq({type: Int32, primary: true, parsed_type: "Int32?", column: "id", auto: true})
        Factory.build_contact.attribute_metadata("name")
          .should eq({type: String, parsed_type: "String", column: "name"})
        Factory.build_address.attribute_metadata("street")
          .should eq({type: String, parsed_type: "String", column: "street"})
      end
    end
  end

  describe "%mapping" do
    describe "converter" do
      postgres_only do
        describe PG::Numeric do
          it "allows passing PG::Numeric" do
            ballance = PG::Numeric.new(1i16, 0i16, 0i16, 0i16, [1i16])
            c = ContactWithFloatMapping.build(ballance: ballance)
            c.ballance.should eq(1.0f64)
            c.ballance.is_a?(Float64)
          end

          it "correctly creates using provided field instead of numeric" do
            ballance = 10f64
            c = ContactWithFloatMapping.build(ballance: ballance)
            c.ballance.should eq(10f64)
            c.ballance.is_a?(Float64).should be_true
          end

          it "correctly loads data from db" do
            ballance = PG::Numeric.new(1i16, 0i16, 0i16, 0i16, [1i16])
            c = ContactWithFloatMapping.create(ballance: ballance)
            contact_with_float = ContactWithFloatMapping.find!(c.id)
            contact_with_float.ballance.should eq(1.0f64)
            contact_with_float.ballance.is_a?(Float64).should be_true
          end
        end
      end
    end

    describe "::columns_tuple" do
      it "returns named tuple with column metadata" do
        metadata = Contact.columns_tuple
        metadata.is_a?(NamedTuple).should be_true
        metadata[:id].is_a?(NamedTuple).should be_true
        metadata[:id][:type].should eq(Int32)
        metadata[:id][:parsed_type].should eq("Int32?")
      end

      it "ignores column aliases" do
        metadata = Author.columns_tuple
        metadata.is_a?(NamedTuple).should be_true
        metadata[:name1].is_a?(NamedTuple).should be_true
        metadata[:name1][:type].should eq(String)
        metadata[:name1][:parsed_type].should eq("String")
      end

      it "includes fields defined in included module" do
        metadata = UserWithModuleMapping.columns_tuple
        metadata.is_a?(NamedTuple).should be_true
        metadata.has_key?(:id).should be_true
        metadata.has_key?(:name).should be_true
        metadata.has_key?(:password_digest).should be_true
        metadata.has_key?(:email).should be_true
      end
    end

    context "columns metadata" do
      it "sets constant" do
        Contact::COLUMNS_METADATA.is_a?(NamedTuple).should be_true
      end

      it "sets primary to true for Primary32 type" do
        Contact::COLUMNS_METADATA[:id][:primary].should be_true
      end

      it "sets primary for Primary64" do
        ContactWithInValidation::COLUMNS_METADATA[:id][:primary].should be_true
      end
    end

    describe ".new" do
      context "loading STI objects from request" do
        it "creates proper objects" do
          Factory.create_twitter_profile
          Factory.create_facebook_profile
          klasses = [] of Profile.class

          Profile.all.each_result_set do |rs|
            record = Profile.new(rs)
            klasses << record.class
          end
          match_array(klasses, [FacebookProfile, TwitterProfile])
        end

        it "raises exception if invalid type was given" do
          p = Factory.create_facebook_profile
          p.update_column("type", "asdasd")
          expect_raises(Jennifer::UnknownSTIType) do
            Profile.all.each_result_set do |rs|
              Profile.new(rs)
            end
          end
        end

        it "creates base class if type field is blank" do
          p = Factory.create_facebook_profile
          p.update_column("type", "")
          executed = false

          Profile.all.each_result_set do |rs|
            Profile.new(rs).class.to_s.should eq("Profile")
            executed = true
          end
          executed.should be_true
        end
      end

      context "from result set" do
        it "properly creates object" do
          executed = false
          Factory.create_contact(name: "Jennifer", age: 20)
          Contact.all.each_result_set do |rs|
            record = Contact.new(rs)
            record.name.should eq("Jennifer")
            record.age.should eq(20)
            executed = true
          end
          executed.should be_true
        end

        it "properly assigns aliased columns" do
          executed = false
          Author.create(name1: "Ann", name2: "OtherAuthor")
          Author.all.each_result_set do |rs|
            record = Author.new(rs)
            record.name1.should eq("Ann")
            record.name2.should eq("OtherAuthor")
            executed = true
          end
          executed.should be_true
        end
      end

      context "from hash" do
        context "with string keys" do
          it "properly creates object" do
            contact = Contact.new({"name" => "Deepthi", "age" => 18, "gender" => "female"})
            contact.name.should eq("Deepthi")
            contact.age.should eq(18)
            contact.gender.should eq("female")
          end

          it "properly maps column aliases" do
            a = Author.new({"name1" => "Gener", "name2" => "Ric"})
            a.name1.should eq("Gener")
            a.name2.should eq("Ric")
          end
        end

        context "with symbol keys" do
          it "properly creates object" do
            contact = Contact.new({:name => "Deepthi", :age => 18, :gender => "female"})
            contact.name.should eq("Deepthi")
            contact.age.should eq(18)
            contact.gender.should eq("female")
          end

          it "properly maps column aliases" do
            a = Author.new({:name1 => "Ran", :name2 => "Dom"})
            a.name1.should eq("Ran")
            a.name2.should eq("Dom")
          end
        end
      end

      context "from named tuple" do
        it "properly creates object" do
          contact = Contact.new({name: "Deepthi", age: 18, gender: "female"})
          contact.name.should eq("Deepthi")
          contact.age.should eq(18)
          contact.gender.should eq("female")
        end

        it "properly maps column aliases" do
          a = Author.new({ name1: "Unk", name2: "Nown" })
          a.name1.should eq("Unk")
          a.name2.should eq("Nown")
        end
      end

      context "without arguments" do
        it "creates object with nil or default values" do
          country = Country.new
          country.id.should be_nil
          country.name.should be_nil
        end

        it "works with default values" do
          c = CountryWithDefault.new
          c.name.should be_nil
          c.virtual.should be_true
        end
      end

      context "model has only id field" do
        it "creates succesfully without arguments" do
          id = OneFieldModel.create.id
          OneFieldModel.find!(id).id.should eq(id)
        end
      end
    end

    describe "::field_count" do
      it "returns correct number of model fields" do
        proper_count = db_specific(
          mysql: -> { 9 },
          postgres: -> { 10 }
        )
        Contact.field_count.should eq(proper_count)
      end
    end

    describe "data types" do
      describe "mapping types" do
        describe "Primary32" do
          it "makes field nillable" do
            Contact.columns_tuple[:id][:parsed_type].should eq("Int32?")
          end
        end

        describe "Primary64" do
          it "makes field nillable" do
            ContactWithInValidation.columns_tuple[:id][:parsed_type].should eq("Int64?")
          end
        end

        describe "user-defined mapping types" do
          it "is accessible if defined in parent class" do
            User::COLUMNS_METADATA[:password_digest].should eq({type: String, column: "password_digest", default: "", parsed_type: "String"})
            User::COLUMNS_METADATA[:email].should eq({type: String, column: "email", default: "", parsed_type: "String"})
          end

          pending "allows to add extra options" do
          end

          pending "allows to override options" do
          end
        end
      end

      describe "BOOLEAN" do
        it "correctly saves and loads" do
          AllTypeModel.create!(bool_f: true)
          AllTypeModel.all.last!.bool_f!.should be_true
        end
      end

      describe "BIGINT" do
        it "correctly saves and loads" do
          AllTypeModel.create!(bigint_f: 15i64)
          AllTypeModel.all.last!.bigint_f!.should eq(15i64)
        end
      end

      describe "INTEGER" do
        it "correctly saves and loads" do
          AllTypeModel.create!(integer_f: 32)
          AllTypeModel.all.last!.integer_f!.should eq(32)
        end
      end

      describe "SHORT" do
        it "correctly saves and loads" do
          AllTypeModel.create!(short_f: 16i16)
          AllTypeModel.all.last!.short_f!.should eq(16i16)
        end
      end

      describe "FLOAT" do
        it "correctly saves and loads" do
          AllTypeModel.create!(float_f: 32f32)
          AllTypeModel.all.last!.float_f!.should eq(32f32)
        end
      end

      describe "DOUBLE" do
        it "correctly saves and loads" do
          AllTypeModel.create!(double_f: 64f64)
          AllTypeModel.all.last!.double_f!.should eq(64f64)
        end
      end

      describe "STRING" do
        it "correctly saves and loads" do
          AllTypeModel.create!(string_f: "string")
          AllTypeModel.all.last!.string_f!.should eq("string")
        end
      end

      describe "VARCHAR" do
        it "correctly saves and loads" do
          AllTypeModel.create!(varchar_f: "string")
          AllTypeModel.all.last!.varchar_f!.should eq("string")
        end
      end

      describe "TEXT" do
        it "correctly saves and loads" do
          AllTypeModel.create!(text_f: "string")
          AllTypeModel.all.last!.text_f!.should eq("string")
        end
      end

      describe Time do
        it "stores to db time converted to UTC" do
          Factory.create_contact
          new_time = Time.local(local_time_zone)
          with_time_zone("Etc/GMT+1") do
            Contact.all.update(created_at: new_time)
            Contact.all.select { [_created_at] }.each_result_set do |rs|
              rs.read(Time).should be_close(new_time, 1.second)
            end
          end
        end

        it "converts values from utc to local" do
          contact = Factory.create_contact
          with_time_zone("Etc/GMT+1") do
            contact.reload.created_at!.should be_close(Time.local(local_time_zone), 1.second)
          end
        end
      end

      describe "TIMESTAMP" do
        it "correctly saves and loads" do
          AllTypeModel.create!(timestamp_f: Time.utc(2016, 2, 15, 10, 20, 30))
          AllTypeModel.all.last!.timestamp_f!.in(UTC).should eq(Time.utc(2016, 2, 15, 10, 20, 30))
        end
      end

      describe "DATETIME" do
        it "correctly saves and loads" do
          AllTypeModel.create!(date_time_f: Time.utc(2016, 2, 15, 10, 20, 30))
          AllTypeModel.all.last!.date_time_f!.in(UTC).should eq(Time.utc(2016, 2, 15, 10, 20, 30))
        end
      end

      describe "DATE" do
        it "correctly saves and loads" do
          AllTypeModel.create!(date_f: Time.utc(2016, 2, 15, 10, 20, 30))
          AllTypeModel.all.last!.date_f!.in(UTC).should eq(Time.utc(2016, 2, 15, 0, 0, 0))
        end
      end

      describe "JSON" do
        it "correctly loads json field" do
          # This checks nillable JSON as well
          c = Factory.create_address(street: "a st.", details: JSON.parse(%(["a", "b", 1])))
          c = Address.find!(c.id)
          c.details.should be_a(JSON::Any)
          c.details![2].as_i.should eq(1)
        end
      end

      postgres_only do
        describe "DECIMAL" do
          it "correctly saves and loads" do
            AllTypeModel.create!(decimal_f: PG::Numeric.new(1i16, 0i16, 0i16, 0i16, [1i16]))
            AllTypeModel.all.last!.decimal_f!.should eq(PG::Numeric.new(1i16, 0i16, 0i16, 0i16, [1i16]))
          end
        end

        describe "OID" do
          it "correctly saves and loads" do
            AllTypeModel.create!(oid_f: 2147483648_u32)
            AllTypeModel.all.last!.oid_f!.should eq(2147483648_u32)
          end
        end

        describe "CHAR" do
          it "correctly saves and loads" do
            AllTypeModel.create!(char_f: "a")
            AllTypeModel.all.last!.char_f!.should eq("a")
          end
        end

        describe "UUID" do
          it "correctly saves and loads" do
            AllTypeModel.create!(uuid_f: "7d61d548-124c-4b38-bc05-cfbb88cfd1d1")
            AllTypeModel.all.last!.uuid_f!.should eq("7d61d548-124c-4b38-bc05-cfbb88cfd1d1")
          end
        end

        describe "TIMESTAMPTZ" do
          it "correctly saves and loads" do
            AllTypeModel.create!(timestamptz_f: Time.local(2016, 2, 15, 10, 20, 30, location: BERLIN))
            # NOTE: ATM this is expected behavior
            AllTypeModel.all.last!.timestamptz_f!.in(UTC).should eq(Time.utc(2016, 2, 15, 9, 20, 30))
          end
        end

        describe "BYTEA" do
          it "correctly saves and loads" do
            AllTypeModel.create!(bytea_f: Bytes[65, 114, 116, 105, 99, 108, 101])
            AllTypeModel.all.last!.bytea_f!.should eq(Bytes[65, 114, 116, 105, 99, 108, 101])
          end
        end

        describe "JSONB" do
          it "correctly saves and loads" do
            AllTypeModel.create!(jsonb_f: JSON.parse(%(["a", "b", 1])))
            AllTypeModel.all.last!.jsonb_f!.should eq(JSON.parse(%(["a", "b", 1])))
          end
        end

        describe "XML" do
          it "correctly saves and loads" do
            AllTypeModel.create!(xml_f: "<html></html>")
            AllTypeModel.all.last!.xml_f!.should eq("<html></html>")
          end
        end

        describe "POINT" do
          it "correctly saves and loads" do
            AllTypeModel.create!(point_f: PG::Geo::Point.new(1.2, 3.4))
            AllTypeModel.all.last!.point_f!.should eq(PG::Geo::Point.new(1.2, 3.4))
          end
        end

        describe "LSEG" do
          it "correctly saves and loads" do
            AllTypeModel.create!(lseg_f: PG::Geo::LineSegment.new(1.0, 2.0, 3.0, 4.0))
            AllTypeModel.all.last!.lseg_f!.should eq(PG::Geo::LineSegment.new(1.0, 2.0, 3.0, 4.0))
          end
        end

        describe "PATH" do
          it "correctly saves and loads" do
            path = PG::Geo::Path.new([PG::Geo::Point.new(1.0, 2.0), PG::Geo::Point.new(3.0, 4.0)], closed: true)
            AllTypeModel.create!(path_f: path)
            AllTypeModel.all.last!.path_f!.should eq(path)
          end
        end

        describe "BOX" do
          it "correctly saves and loads" do
            AllTypeModel.create!(box_f: PG::Geo::Box.new(1.0, 2.0, 3.0, 4.0))
            AllTypeModel.all.last!.box_f!.should eq(PG::Geo::Box.new(1.0, 2.0, 3.0, 4.0))
          end
        end
      end

      mysql_only do
        describe "TINYINT" do
          it "correctly saves and loads" do
            AllTypeModel.create!(tinyint_f: 8i8)
            AllTypeModel.all.last!.tinyint_f!.should eq(8i8)
          end
        end

        describe "DECIMAL" do
          it "correctly saves and loads" do
            AllTypeModel.create!(decimal_f: 64f64)
            AllTypeModel.all.last!.decimal_f!.should eq(64f64)
          end
        end

        describe "BLOB" do
          it "correctly saves and loads" do
            AllTypeModel.create!(blob_f: Bytes[65, 114, 116, 105, 99, 108, 101])
            AllTypeModel.all.last!.blob_f!.should eq(Bytes[65, 114, 116, 105, 99, 108, 101])
          end
        end
      end

      context "nillable field" do
        context "passed with ?" do
          it "properly sets field as nillable" do
            typeof(ContactWithNillableName.new.name).should eq(String?)
          end
        end

        context "passed as union" do
          it "properly sets field class as nillable" do
            typeof(Factory.build_contact.created_at).should eq(Time?)
          end
        end
      end

      describe "ENUM (database)" do
        it "properly loads enum" do
          c = Factory.create_contact(name: "sam", age: 18)
          Contact.find!(c.id).gender.should eq("male")
        end

        it "properly search via enum" do
          Factory.create_contact(name: "sam", age: 18, gender: "male")
          Factory.create_contact(name: "Jennifer", age: 18, gender: "female")
          Contact.all.count.should eq(2)
          Contact.where { _gender == "male" }.count.should eq(1)
        end
      end

      context "mismatching data type" do
        it "raises DataTypeMismatch exception" do
          ContactWithNillableName.create({name: nil})
          expect_raises(::Jennifer::DataTypeMismatch, "Column ContactWithCustomField.name is expected to be a String but got Nil.") do
            ContactWithCustomField.all.last!
          end
        end

        it "raised exception includes query explanation" do
          ContactWithNillableName.create({name: nil})
          expect_raises(::Jennifer::DataTypeMismatch, select_regexp) do
            ContactWithCustomField.all.last!
          end
        end
      end

      context "mismatching data type during loading from hash" do
        it "raises DataTypeCasting exception" do
          c = ContactWithNillableName.create({name: nil})
          Factory.create_address({:contact_id => c.id})
          expect_raises(::Jennifer::DataTypeCasting, "Column Contact.name can't be casted from Nil to it's type - String") do
            Address.all.eager_load(:contact).last!
          end
        end

        it "raised exception includes query explanation" do
          ContactWithNillableName.create({name: nil})
          expect_raises(::Jennifer::DataTypeMismatch, select_regexp) do
            ContactWithCustomField.all.last!
          end
        end
      end

      postgres_only do
        describe Array do
          it "loads nilable array" do
            c = Factory.create_contact({:name => "sam", :age => 18, :gender => "male", :tags => [1, 2]})
            c.tags!.should eq([1, 2])
            Contact.all.first!.tags!.should eq([1, 2])
          end

          it "creates object with array" do
            ContactWithArray.build({tags: [1, 2]}).tags.should eq([1, 2])
          end
        end
      end
    end

    describe "attribute getter" do
      it "provides getters" do
        c = Factory.build_contact(name: "a")
        c.name.should eq("a")
      end
    end

    describe "predicate method" do
      it { AddressWithNilableBool.new({main: true}).main?.should be_true }
      it { AddressWithNilableBool.new({main: false}).main?.should be_false }
      it { AddressWithNilableBool.new({main: nil}).main?.should be_false }
    end

    describe "attribute setter" do
      it "provides setters" do
        c = Factory.build_contact(name: "a")
        c.name = "b"
        c.name.should eq("b")
      end

      context "with DBAny" do
        it do
          hash = { :name => "new_name" } of Symbol => Jennifer::DBAny
          c = Factory.build_contact(name: "a")
          c.name = hash[:name]
          c.name.should eq("new_name")
        end
      end

      context "with subset of DBAny" do
        it do
          hash = { :name => "new_name", :age => 12 }
          c = Factory.build_contact(name: "a")
          c.name = hash[:name]
          c.name.should eq("new_name")
        end

        context "with wrong type" do
          it do
            hash = { :name => "new_name", :age => 12 }
            c = Factory.build_contact(name: "a")
            expect_raises(TypeCastError) do
              c.name = hash[:age]
            end
          end
        end
      end
    end

    describe "attribute alias" do
      it "provides aliases for the getters and setters" do
        a = Author.build(name1: "an", name2: "author")
        a.name1 = "the"
        a.name1.should eq "the"
      end
    end

    describe "criteria attribute class shortcut" do
      it "adds criteria shortcut for class" do
        c = Contact._name
        c.table.should eq("contacts")
        c.field.should eq("name")
      end
    end

    describe "#primary" do
      context "default primary field" do
        it "returns id value" do
          c = Factory.build_contact
          c.id = -1
          c.primary.should eq(-1)
        end
      end

      context "custom field" do
        it "returns value of custom primary field" do
          p = Factory.build_passport
          p.enn = "1qaz"
          p.primary.should eq("1qaz")
        end
      end
    end

    describe "#update_columns" do
      context "attribute exists" do
        it "sets attribute if value has proper type" do
          c = Factory.create_contact
          c.update_columns({:name => "123"})
          c.name.should eq("123")
          c = Contact.find!(c.id)
          c.name.should eq("123")
        end

        it "raises exception if value has wrong type" do
          c = Factory.create_contact
          expect_raises(::Jennifer::BaseException) do
            c.update_columns({:name => 123})
          end
        end
      end

      context "no such setter" do
        it "raises exception" do
          c = Factory.build_contact
          expect_raises(::Jennifer::BaseException) do
            c.update_columns({:asd => 123})
          end
        end
      end
    end

    describe "#update_column" do
      context "attribute exists" do
        it "sets attribute if value has proper type" do
          c = Factory.create_contact
          c.update_column(:name, "123")
          c.name.should eq("123")
          c = Contact.find!(c.id)
          c.name.should eq("123")
        end

        it "raises exception if value has wrong type" do
          c = Factory.create_contact
          expect_raises(::Jennifer::BaseException) do
            c.update_column(:name, 123)
          end
        end
      end

      context "no such setter" do
        it "raises exception" do
          c = Factory.build_contact
          expect_raises(::Jennifer::BaseException) do
            c.update_column(:asd, 123)
          end
        end
      end
    end

    describe "#set_attribute" do
      context "when attribute is virtual" do
        it do
          p = Factory.build_profile
          p.set_attribute(:virtual_parent_field, "virtual value")
          p.virtual_parent_field.should eq("virtual value")
        end
      end

      context "attribute exists" do
        it "sets attribute if value has proper type" do
          c = Factory.build_contact
          c.set_attribute(:name, "123")
          c.name.should eq("123")
        end

        it "raises exception if value has wrong type" do
          c = Factory.build_contact
          expect_raises(::Jennifer::BaseException) do
            c.set_attribute(:name, 123)
          end
        end

        it "marks changed field as modified" do
          c = Factory.build_contact
          c.set_attribute(:name, "asd")
          c.name_changed?.should be_true
        end
      end

      context "no such setter" do
        it "raises exception" do
          c = Factory.build_contact
          expect_raises(::Jennifer::BaseException) do
            c.set_attribute(:asd, 123)
          end
        end
      end
    end

    describe "#attribute" do
      context "when attribute is virtual" do
        it "" do
          p = Factory.build_profile
          p.virtual_parent_field = "value"
          p.attribute(:virtual_parent_field).should eq("value")
        end
      end

      it "returns attribute value by given name" do
        c = Factory.build_contact(name: "Jessy")
        c.attribute("name").should eq("Jessy")
        c.attribute(:name).should eq("Jessy")
      end

      it do
        c = Factory.build_contact(name: "Jessy")
        expect_raises(::Jennifer::BaseException) do
          c.attribute("missing")
        end
      end

      it "returns fields names only (no aliased columns)" do
        a = Author.build(name1: "TheO", name2: "TherExample")
        a.attribute("name1").should eq("TheO")
        a.attribute(:name2).should eq("TherExample")
        expect_raises(::Jennifer::BaseException) do
          a.attribute("first_name")
        end
        expect_raises(::Jennifer::BaseException) do
          a.attribute(:last_name)
        end
      end
    end

    describe "#arguments_to_save" do
      it "returns named tuple with correct keys" do
        c = Factory.build_contact
        c.name = "some another name"
        r = c.arguments_to_save
        r.is_a?(NamedTuple).should be_true
        r.keys.should eq({:args, :fields})
      end

      it "returns tuple with empty arguments if no field was changed" do
        r = Factory.build_contact.arguments_to_save
        r[:args].empty?.should be_true
        r[:fields].empty?.should be_true
      end

      it "returns tuple with changed arguments" do
        c = Factory.build_contact
        c.name = "some new name"
        r = c.arguments_to_save
        r[:args].should eq(db_array("some new name"))
        r[:fields].should eq(db_array("name"))
      end

      it "returns aliased columns" do
        a = Author.create(name1: "Fin", name2: "AlAuthor")
        a.name1 = "NotFin"
        r = a.arguments_to_save
        r[:args].should eq(db_array("NotFin"))
        r[:fields].should eq(db_array("first_name"))
      end
    end

    describe "#arguments_to_insert" do
      it "returns named tuple with :args and :fields keys" do
        r = Factory.build_profile.arguments_to_insert
        r.is_a?(NamedTuple).should be_true
        r.keys.should eq({:args, :fields})
      end

      it "returns tuple with all fields" do
        r = Factory.build_profile.arguments_to_insert
        match_array(r[:fields], %w(login contact_id type))
      end

      it "returns tuple with all values" do
        r = Factory.build_profile.arguments_to_insert
        match_array(r[:args], db_array("some_login", nil, "Profile"))
      end

      it "returns aliased columns" do
        r = Author
          .build(name1: "Prob", name2: "AblyTheLast")
          .arguments_to_insert
        match_array(r[:args], db_array("Prob", "AblyTheLast"))
        match_array(r[:fields], %w(first_name last_name))
      end

      it "includes non autoincrementable primary field" do
        r = NoteWithManualId.new({ id: 12, text: "test" }).arguments_to_insert
        match_array(r[:args], db_array(12, "test", nil, nil))
        match_array(r[:fields], %w(id text created_at updated_at))
      end
    end

    describe "#to_h" do
      it "creates hash with symbol keys" do
        hash = Factory.build_profile(login: "Abdul").to_h
        # NOTE: virtual field isn't included
        hash.keys.should eq(%i(id login contact_id type))
      end

      it "creates hash with symbol keys that does not contain the column names" do
        hash = Author.build(name1: "IsThi", name2: "SFinallyOver").to_h
        hash.keys.should eq(%i(id name1 name2))
      end
    end

    describe "#to_str_h" do
      it "creates hash with string keys" do
        hash = Factory.build_profile(login: "Abdul").to_str_h
        # NOTE: virtual field isn't included
        hash.keys.should eq(%w(id login contact_id type))
      end

      it "creates hash with string keys that does not contain the column names" do
        hash = Author.build(name1: "NoIt", name2: "SNot").to_str_h
        hash.keys.should eq(%w(id name1 name2))
      end
    end

    describe ".primary_auto_incrementable?" do
      it { Note.primary_auto_incrementable?.should be_true }
      it { NoteWithManualId.primary_auto_incrementable?.should be_false }
    end
  end

  describe "%with_timestamps" do
    it "adds callbacks" do
      Contact::CALLBACKS[:create][:before].should contain("__update_created_at")
      Contact::CALLBACKS[:save][:before].should contain("__update_updated_at")
    end
  end

  describe "#__update_created_at" do
    it "updates created_at field" do
      c = Factory.build_contact
      c.created_at.should be_nil
      c.__update_created_at
      c.created_at!.should_not be_nil
      ((c.created_at! - Time.local).total_seconds < 1).should be_true
    end
  end

  describe "#__update_updated_at" do
    it "updates updated_at field" do
      c = Factory.build_contact
      c.updated_at.should be_nil
      c.__update_updated_at
      c.updated_at!.should_not be_nil
      ((c.updated_at! - Time.local).total_seconds < 1).should be_true
    end
  end
end
