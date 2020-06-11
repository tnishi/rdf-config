class RDFConfig
  class Schema
    class Chart
      require 'rexml/document'
      class REXML::Element
        def add_attribute_by_hash(attr_hash)
          attr_hash.each do |name, value|
            add_attribute(name.to_s, value)
          end
        end
      end

      require 'rdf-config/schema/chart/svg_element_opt'
      require 'rdf-config/schema/chart/svg_element'
      include SVGElementOpt
      include SVGElement

      Position = Struct.new(:x, :y)
      ArrowPosition = Struct.new(:x1, :y1, :x2, :y2)

      START_X = 50.freeze
      START_Y = 10.freeze
      YPOS_CHANGE_NUM_OBJ = 8.freeze

      def initialize(config)
        @model = Model.new(config)
        @svg_element = svg_element

        @current_pos = Position.new(START_X, START_Y)
        @subject_queue = []
        @generated_subjects = []
        @element_pos = {}
      end

      def generate
        @model.subjects.each do |subject|
          generate_subject(subject)
        end

        output_svg
      end

      def output_svg
        width = @element_pos.values.flatten.map(&:x).max + RECT_WIDTH + 100
        height = @element_pos.values.flatten.map(&:y).max + RECT_HEIGHT + MARGIN_RECT + 100
        svg_opts = {
            width: "#{width}px",
            height: "#{height}px",
            viewBox: "-0.5 -0.5 #{width} #{height}"
        }
        @svg_element.add_attribute_by_hash(svg_opts)

        xml = xml_doc
        xml.add_element(@svg_element)
        xml.write($stdout, 2)
      end

      def generate_subject(subject)
        return if @generated_subjects.include?(subject.name)

        unless @element_pos.key?(subject.object_id)
          @element_pos[subject.object_id] = []
        end
        @subject_queue.push(subject)
        add_element_position

        if subject.blank_node?
          add_to_svg(blank_node_elements(@current_pos))
        else
          inner_texts = [subject.name, subject.value]
          add_to_svg(uri_elements(@current_pos, inner_texts, :instance))
        end

        subject.predicates.each do |predicate|
          predicate.objects.each do |object|
            generate_predicate_object(predicate, object)
            move_to_next_object
          end
        end

        @generated_subjects << subject.name unless subject.blank_node?
        @subject_queue.pop
      end

      def generate_predicate_object(predicate, object)
        move_to_predicate
        generate_predicate(predicate, object)

        # move object position after generating predicate
        @current_pos.x += PREDICATE_AREA_WIDTH
        generate_object(predicate, object)
      end

      def generate_predicate(predicate, object)
        add_to_svg(
            predicate_arrow_elements(predicate_arrow_position(object), predicate)
        )
      end

      def generate_object(predicate, object)
        add_element_position

        if object.instance_of?(Model::Subject)
          generate_subject(object)
        elsif object.blank_node?
          generate_subject(object.value)
        elsif predicate.rdf_type?
          add_to_svg(uri_elements(@current_pos, object.name, :class))
        else
          inner_texts = [object.name, object.value]
          case object
          when Model::Unknown
            add_to_svg(unknown_object_elements(@current_pos, inner_texts[0]))
          when Model::URI
            add_to_svg(uri_elements(@current_pos, inner_texts))
          when Model::Literal
            add_to_svg(object_literal_elements(@current_pos, inner_texts, object.type))
          end
        end
      end

      def subject_position(subject)
        @element_pos[subject.object_id].first
      end

      def move_to_predicate
        @current_pos.x = if current_subject.blank_node?
                           subject_position(current_subject).x + BNODE_RADIUS * 2
                         else
                           subject_position(current_subject).x + RECT_WIDTH
                         end
      end

      def predicate_arrow_position(object)
        y1 = if current_subject.blank_node?
               subject_position(current_subject).y + BNODE_RADIUS
             else
               subject_position(current_subject).y + RECT_HEIGHT / 2
             end

        y2 = if object.blank_node?
               @current_pos.y + BNODE_RADIUS
             else
               @current_pos.y + RECT_HEIGHT / 2
             end

        ArrowPosition.new(@current_pos.x, y1, @current_pos.x + PREDICATE_AREA_WIDTH, y2)
      end

      def move_to_next_object
        @current_pos.y = @element_pos.values.flatten.map(&:y).max + RECT_HEIGHT + MARGIN_RECT
      end

      def current_subject
        @subject_queue.last
      end

      def num_objects
        # notice @element_pos include subject position
        @element_pos[current_subject.object_id].size - 1
      end

      def xml_doc
        doc = REXML::Document.new
        doc.add REXML::XMLDecl.new('1.0', 'UTF-8')
        doc.add REXML::DocType.new('svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd"')

        doc
      end

      def add_to_svg(element)
        case element
        when Array
          element.each do |elem|
            @svg_element.add_element(elem)
          end
        else
          @svg_element.add_element(element)
        end
      end

      def add_element_position
        @element_pos[current_subject.object_id] << @current_pos.dup
      end

      def style_value_by_hash(hash)
        hash.map { |name, value| "#{name}: #{value}" }.join('; ')
      end

      def distance(x1, y1, x2, y2)
        dx = (x2 - x1).abs.to_f
        dy = (y2 - y1).abs.to_f

        Math.sqrt(dx**2 + dy**2)
      end
    end

  end
end
