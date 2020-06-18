class RDFConfig
  class SPARQL
    class WhereBuilder < SPARQL
      INDENT_TEXT = '    '.freeze

      class Triple
        attr_reader :subject, :predicate, :object

        def initialize(subject, predicate, object)
          @subject = subject
          @predicate = predicate

          @object = if object.is_a?(Array) && object.size == 1
                      object.first
                    else
                      object
                    end
        end

        def rdf_type?
          %w[a rdf:type].include?(@predicate)
        end

        def subject_is_blank_node?
          @subject[0] == '_'
        end

        def object_is_blank_node?
          @object[0] == '_'
        end

        def to_s(indent = '', is_first_triple = true, is_last_triple = true)
          line = if is_first_triple
                   "#{indent}#{subject} "
                 else
                   "#{indent * 2}"
                 end
          line = "#{line}#{predicate} #{object}"
          line = "#{line} #{is_last_triple ? '.' : ';'}"

          line
        end

        def ==(other)
          @subject == other.subject && @predicate == other.predicate && @object == other.object
        end
      end

      def initialize(config, opts = {})
        super

        @triples = {
          required: [],
          optional: []
        }
        @filter_lines = []

        @subject_class = {}
        @blank_node = {}
        @bnode_number = 1
        @depth = 1

        generate_triples
      end

      def build
        lines = ['WHERE {']
        lines += values_lines(parameters)
        lines += required_lines
        lines += optional_lines
        lines += filter_lines
        lines << '}'

        lines
      end

      def values_lines(parameters)
        lines = []

        parameters.each do |variable_name, value|
          value = "{{#{variable_name}}}" if template?
          object = model.find_object(variable_name)
          value = %("#{value}") if object.is_a?(RDFConfig::Model::Literal)

          lines << "#{indent}VALUES ?#{variable_name} { #{value} }"
        end

        lines
      end

      def required_lines
        lines = []
        @triples[:required].map(&:subject).uniq.each do |subject|
          lines += lines_by_subject(@triples[:required].select { |triple| triple.subject == subject })
        end

        lines
      end

      def optional_lines
        lines = []
        @triples[:optional].each do |triple|
          lines << "#{indent}OPTIONAL{ #{triple.to_s} }"
        end

        lines
      end

      def filter_lines
        @filter_lines.uniq
      end

      def generate_triples
        variables.each do |variable_name|
          next if model.subject?(variable_name)

          triple_in_model = model.find_by_object_name(variable_name)
          next if triple_in_model.nil?

          if triple_in_model.predicates.size > 1
            generate_triples_with_bnode(triple_in_model)
          else
            generate_triple_without_bnode(triple_in_model)
          end
        end
      end

      private

      def generate_triple_without_bnode(triple_in_model)
        is_optional = optional_phrase?(triple_in_model.predicate)
        subject = "?#{triple_in_model.subject.name}"
        unless @subject_class.key?(subject)
          rdf_types = @model.find_subject(triple_in_model.subject.name).types
          @subject_class[subject] = rdf_types
        end

        add_triple(Triple.new(subject, 'a', @subject_class[subject]), false)
        add_triple(Triple.new(subject, triple_in_model.predicates.first.uri, "?#{triple_in_model.object.name}"),
                   is_optional)
      end

      def generate_triples_with_bnode(triple_in_model)
        is_optional = optional_phrase?(triple_in_model.predicate)
        bnode_rdf_types = model.bnode_rdf_types(triple_in_model)

        if use_property_path?(bnode_rdf_types)
          add_triple(Triple.new("?#{triple_in_model.subject.name}",
                                triple_in_model.property_path,
                                "?#{triple_in_model.object_name}"),
                     is_optional
          )
        else
          triples_with_bnode_class(triple_in_model, bnode_rdf_types)
        end
      end

      def triples_with_bnode_class(triple_in_model, bnode_rdf_types)
        is_optional = optional_phrase?(triple_in_model.predicates.first)
        predicates = triple_in_model.predicates
        num_predicates = predicates.size
        bnode = blank_node(predicates[0..0])

        add_triple(Triple.new("?#{triple_in_model.subject.name}", triple_in_model.predicates.first.uri, bnode),
                   is_optional)

        unless bnode_rdf_types.first.nil?
          # Blank node has rdf:type
          bnode_id = bnode_id(bnode)
          if bnode_rdf_types.first.size == 1
            add_triple(Triple.new(bnode, 'a', bnode_rdf_types.first.first), false)
          else
            bnode_class_var = "?_b#{bnode_id}_class"
            add_triple(Triple.new(bnode, 'a', bnode_class_var), false)
            add_filter_line("#{INDENT_TEXT}FILTER(#{bnode_class_var} IN (#{bnode_rdf_types.first.join(', ')}))")
          end
        end

        1.upto(num_predicates - 2) do |i|
          object_bnode = blank_node(triple_in_model.predicates[0..i])
          add_triple(Triple.new(bnode, triple_in_model.predicates[i].uri, object_bnode), false)

          bnode = blank_node(triple_in_model.predicates[0..i])
          unless bnode_rdf_types[i].nil?
            add_triple(Triple.new(bnode, 'a', bnode_rdf_types[i]), false)
          end
        end
        add_triple(Triple.new(bnode, triple_in_model.predicates.last.uri, "?#{triple_in_model.object_name}"),
                   optional_phrase?(triple_in_model.predicate))
      end

      def lines_by_subject(triples)
        lines = []

        subject = triples.first.subject
        if @subject_class[subject].is_a?(String)
          triples = [Triple.new(subject, 'a', @subject_class[subject])] + triples
        end

        rdf_type_triple = triples.select(&:rdf_type?).first
        if !rdf_type_triple.nil? && rdf_type_triple.object.is_a?(Array) && rdf_type_triple.object.size > 1
          triples = triples.reject { |triple| triple.equal?(rdf_type_triple) }
        end

        triples.each do |triple|
          lines << triple.to_s(indent, triple.object == triples.first.object, triple.object == triples.last.object)
        end

        lines
      end

      def use_property_path?(bnode_rdf_types)
        flatten = bnode_rdf_types.flatten
        flatten.uniq.size == 1 && flatten.first.nil?
      end

      def indent(depth_increment = 0)
        "#{INDENT_TEXT * (@depth + depth_increment)}"
      end

      def add_triple(triple, is_optional)
        case triple
        when Array
          triple.each do |t|
            add_triple(t, is_optional)
          end
        else
          if is_optional
            @triples[:optional] << triple unless @triples[:optional].include?(triple)
          else
            @triples[:required] << triple unless @triples[:required].include?(triple)
          end
        end
      end

      def add_blank_node(predicates)
        bnode = "_:b#{@bnode_number}"
        @blank_node[predicates] = bnode
        @bnode_number += 1

        bnode
      end

      def blank_node(predicates)
        if @blank_node.key?(predicates)
          @blank_node[predicates]
        else
          add_blank_node(predicates)
        end
      end

      def bnode_id(bnode)
        /\A_\:b(\d+)\z/ =~ bnode

        $1
      end

      def optional_phrase?(predicate_in_model)
        cardinality = predicate_in_model.cardinality
        cardinality.is_a?(RDFConfig::Model::Cardinality) && (cardinality.min.nil? || cardinality.min == 0)
      end

      def template?
        @opts.key?(:template) && @opts[:template] == true
      end

      def add_filter_line(line)
        @filter_lines << line
      end
    end
  end
end
