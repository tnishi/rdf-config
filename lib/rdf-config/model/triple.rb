class RDFConfig
  class Model
    Cardinality = Struct.new(:min, :max)

    class Triple
      attr_reader :subject, :predicates, :object

      def initialize(subject, predicates, object)
        @subject = subject
        @predicates = predicates
        @object = object
      end

      def property_path
        @predicates.map(&:uri).join(' / ')
      end

      class << self
        def instances(subject_hash, prefix_hash = nil)
          @@prefix_hash = prefix_hash.dup unless prefix_hash.nil?

          subject_data = subject_hash.keys.first
          if subject_data.is_a?(String)
            @@subject_hash = subject_hash
            @@predicate_uris = []
          end

          triples = []
          subject_hash[subject_data].each do |predicate_object_hash|
            triples += proc_predicate_object(predicate_object_hash)
          end

          triples
        end

        def create_instance(object_data)
          subject = Subject.new(@@subject_hash, @@prefix_hash)
          predicates = @@predicate_uris.map { |predicate_uri| Predicate.new(predicate_uri, @@prefix_hash) }
          object = Object.instance(object_data, @@prefix_hash)

          Triple.new(subject, predicates, object)
        end

        def proc_predicate_object(predicate_object_hash)
          predicate_uri = predicate_object_hash.keys.first
          @@predicate_uris << predicate_uri
          object_data = predicate_object_hash[predicate_uri]
          triples = proc_object_data(object_data)
          @@predicate_uris.pop

          triples
        end

        def proc_object_data(object_data)
          triples = []

          case object_data
          when String, Hash
            triples << create_instance(object_data)
          when Array
            object_data.each do |data|
              case data
              when Array
                triples += data.map { |obj_data| create_instance(obj_data) }
              when Hash
                triples += proc_object_hash(data)
              end
            end
          end

          triples
        end

        def proc_object_hash(object_hash)
          variable_name = object_hash.keys.first
          case variable_name
          when Array
            # consider object is blank node
            instances(object_hash)
          when String
            [create_instance(object_hash)]
          end
        end
      end
    end

    class Subject
      attr_reader :name, :value, :predicates

      def initialize(subject_hash, prefix_hash = {})
        @prefix_hash = prefix_hash

        key = subject_hash.keys.first
        if key.is_a?(Array)
          @name = key
          @value = nil
        else
          @name, @value = key.split(/\s+/, 2)
        end

        @predicates = []
        subject_hash.each do |subject_data, predicate_object_hashes|
          add_predicates(predicate_object_hashes)
        end
      end

      def types
        rdf_type_predicates = @predicates.select { |predicate| predicate.rdf_type? }
        raise SubjectClassNotFound, "Subject: #{@name}: rdf:type not found." if rdf_type_predicates.empty?

        rdf_type_predicates.map { |predicate| predicate.objects.map(&:name) }.flatten
      end

      def type
        types.join(', ')
      end

      def blank_node?
        @name.is_a?(Array)
      end

      def add_predicates(predicate_object_hashes)
        predicate_object_hashes.each do |predicate_object_hash|
          add_predicate(predicate_object_hash)
        end
      end

      def add_predicate(predicate_object_hash)
        predicate_uri = predicate_object_hash.keys.first
        predicate = Predicate.new(predicate_uri, @prefix_hash)
        object_data = predicate_object_hash[predicate_uri]
        case object_data
        when String, Hash
          predicate.add_object(object_data)
        when Array
          predicate_object_hash[predicate_uri].each do |object_hash|
            predicate.add_object(object_hash)
          end
        end

        @predicates << predicate
      end
      
      class SubjectClassNotFound < StandardError; end
    end

    class Predicate
      attr_reader :uri, :objects, :cardinality

      def initialize(predicate, prefix_hash = {})
        @uri = predicate
        @prefix_hash = prefix_hash
        @cardinality = nil

        @objects = []

        interpret_cardinality
      end

      def add_object(object_data)
        @objects << Object.instance(object_data, @prefix_hash)
      end

      def rdf_type?
        %w[a rdf:type].include?(@uri)
      end

      def sparql_optional_phrase?
        @cardinality.is_a?(Cardinality) && (@cardinality.min.nil? || @cardinality.min == 0)
      end

      private

      def interpret_cardinality
        last_char = @uri[-1]
        case last_char
        when '?', '*', '+'
          proc_char_cardinality(last_char)
        when '}'
          proc_range_cardinality
        end
      end

      def proc_char_cardinality(cardinality)
        @uri = @uri[0..-2]

        case cardinality
        when '?'
          @cardinality = Cardinality.new(0, 1)
        when '*'
          @cardinality = Cardinality.new(0, nil)
        when '+'
          @cardinality = Cardinality.new(1, nil)
        end
      end

      def proc_range_cardinality
        pos = @uri.rindex('{')
        range = @uri[pos + 1..-2]
        @uri = @uri[0..pos - 1]
        if range.index(',')
          min, max = range.split(/\s*,\s*/)
          @cardinality = Cardinality.new(min.to_s == '' ? nil : min.to_i, max.to_s == '' ? nil : max.to_i)
        else
          @cardinality = Cardinality.new(range.to_i, range.to_i)
        end
      end
    end

    class Object
      attr_reader :name, :value

      def initialize(object, prefix_hash = {})
        case object
        when Hash
          @name = object.keys.first
          @value = object[@name]
        else
          @name = object
          @value = nil
        end
      end

      def type
        ''
      end

      def data_type_by_string_value(value)
        if /\^\^(\w+)\:(.+)\z/ =~ value
          if $1 == 'xsd'
            case $2
            when 'string'
              'String'
            when 'integer'
              'Int'
            else
              $2.capitalize
            end
          else
            "#{$1}:#{$2}"
          end
        else
          'String'
        end
      end

      def uri?
        false
      end

      def literal?
        false
      end

      def blank_node?
        false
      end

      class << self
        def instance(object, prefix_hash = {})
          case object
          when Hash
            name = object.keys.first
            value = object[name]
          when String
            # object is object value, name is not available
            name = nil
            value = object
          end

          if blank_node?(name)
            BlankNode.new(object, prefix_hash)
          else
            if value.nil?
              Unknown.new(object, prefix_hash)
            else
              case format(value, prefix_hash)
              when :uri
                URI.new(object)
              when :literal
                Literal.new(object)
              end
            end
          end
        end

        def format(value, prefix_hash = {})
          case value
          when String
            if /\A<.+\>\z/ =~ value
              :uri
            else
              prefix, local_part = value.split(':')
              if prefix_hash.keys.include?(prefix)
                :uri
              else
                :literal
              end
            end
          else
            :literal
          end
        end

        def blank_node?(object_name)
          case object_name
          when Array
            true
          when String
            @name == '[]'
          else
            false
          end
        end
      end
    end

    class URI < RDFConfig::Model::Object
      def initialize(object, prefix_hash = {})
        super
      end

      def type
        'URI'
      end

      def uri?
        true
      end
    end

    class Literal < RDFConfig::Model::Object
      def initialize(object_hash, prefix_hash = {})
        super
      end

      def type
        case @value
        when Integer
          'Int'
        when String
          data_type_by_string_value(@value)
        else
          @value.class.to_s
        end
      end

      def literal?
        true
      end
    end

    class BlankNode < RDFConfig::Model::Object
      def initialize(object, prefixe_hash = {})
        super
        @value = Subject.new({ @name => @value }, prefixe_hash)
      end

      def type
        'BN'
      end

      def blank_node?
        true
      end
    end

    class Unknown < RDFConfig::Model::Object
      def initialize(object, prefix_hash = {})
        super
      end

      def type
        'N/A'
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  require 'yaml'
  require File.expand_path('../model.rb', __dir__)

  target = ARGV[0]
  model = RDFConfig::Model.new("config/#{target}")
  subjects = model.subjects
  subjects.each do |subject|
    subject.predicates.each do |predicate|
      predicate.objects.each do |object|

      end
    end
  end
end
