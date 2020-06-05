class RDFConfig
  class Schema
    class Senbero
      def initialize(model)
        @model = model
      end

      def color_subject(str)
        "\033[35m#{str}\033[0m"
      end

      def color_predicate(str)
        "\033[33m#{str}\033[0m"
      end

      def color_object(str)
        "\033[36m#{str}\033[0m"
      end

      def generate
        triples = @model.triples
        subject_names = triples.map { |triple| triple.subject.name }.uniq

        seen = {}
        triples.each_with_index do |triple, i|
          subject = triple.subject
          unless seen.keys.include?(subject.name)
            seen[subject.name] = {}

            # output subject
            subject_class = subject.type
            subject_color = color_subject(subject.name)
            puts "#{subject_color} (#{subject_class})"
          end

          # output predicate
          next if triple.predicates.last.rdf_type?
          predicate_color = color_predicate(triple.property_path)
          is_last_predicate = triples.size == i + 1 ||  subject.name != triples[i + 1].subject.name
          if is_last_predicate
            puts "    `-- #{predicate_color}"
          else
            puts "    |-- #{predicate_color}"
          end

          # output object
          object = triple.object
          object_label = case object
                         when RDFConfig::Model::URI
                           object.value
                         when RDFConfig::Model::Literal
                           if subject_names.include?(object.value)
                             color_subject(object.value)
                           else
                             object.value.inspect
                           end
                         else
                           'N/A'
                         end

          object_color = color_object(object.name)
          is_last_object = triples.size == i + 1 || triple.property_path != triples[i + 1].property_path
          if is_last_predicate
            if is_last_object
              puts "            `-- #{object_color} (#{object_label})"
            else
              puts "            |-- #{object_color} (#{object_label})"
            end
          else
            if is_last_object
              puts "    |       `-- #{object_color} (#{object_label})"
            else
              puts "    |       |-- #{object_color} (#{object_label})"
            end
          end
        end
      end

    end
  end
end

if $PROGRAM_NAME == __FILE__
  require 'yaml'
  require File.expand_path('../model.rb', __dir__)
  require File.expand_path('../model/triple.rb', __dir__)
  target = ARGV[0]
  model = RDFConfig::Model.new("config/#{target}")

  senbro = RDFConfig::Schema::Senbero.new(model)
  senbro.generate
end
