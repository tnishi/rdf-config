class RDFConfig

  class Model
    include Enumerable

    attr_reader :subjects

    def initialize(config)
      @config = config
      @subjects = []

      generate_triples
    end

    def each
      @triples.each { |t| yield(t) }
    end

    def find_subject(subject_name)
      @subjects.select { |subject| subject.name == subject_name }.first
    end

    def subject?(variable_name)
      !find_subject(variable_name).nil?
    end

    def find_object(object_name)
      @triples.map(&:object).select { |object| object.name == object_name }.first
    end

    def find_by_object_name(object_name)
      @triples.select { |triple| triple.object_name == object_name }.first
    end

    def [](idx)
      @triples[idx]
    end

    def size
      @size ||= @triples.size
    end

    private

    def generate_triples
      @triples = []
      @predicates = []

      @config.model.each do |subject_hash|
        @subjects << Model::Subject.new(subject_hash, @config.prefix)
      end

      @subjects.each do |subject|
        @subject = subject
        proc_subject(subject)
      end
    end

    def proc_subject(subject)
      subject.predicates.each do |predicate|
        @predicates << predicate
        proc_predicate(predicate)
        @predicates.pop
      end
    end

    def proc_predicate(predicate)
      predicate.objects.each_with_index do |object, i|
        proc_object(predicate, object, i)
      end
    end

    def proc_object(predicate, object, idx)
      if object.blank_node?
        proc_subject(object.value)
      else
        subject_as_object = find_subject(object.value)
        if subject_as_object.nil?
          add_triple(Triple.new(@subject, Array.new(@predicates), object))
        else
          subject_as_object.add_as_object(@subject.name, object)
          add_triple(Triple.new(@subject, Array.new(@predicates), subject_as_object))
          predicate.objects[idx] = subject_as_object
        end
      end
    end

    def add_triple(triple)
      @triples << triple
    end
  end
end
