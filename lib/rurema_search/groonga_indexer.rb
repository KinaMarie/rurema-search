# Copyright (c) 2010 Kouhei Sutou <kou@clear-code.com>
#
# License: LGPLv3+

module RuremaSearch
  class GroongaIndexer
    attr_accessor :base_time
    def initialize(database, method_database, function_database)
      @database = database
      @method_database = method_database
      @function_database = function_database
      @base_time = nil
    end

    def index
      @method_database.classes.each do |klass|
        index_class(klass)
      end
      @method_database.docs.each do |doc|
        index_document(doc)
      end
      @method_database.libraries.each do |library|
        index_library(library)
      end
      @function_database.functions.each do |function|
        index_function(function)
      end
    end

    private
    def version
      @version ||= @method_database.properties["version"]
    end

    def encoding
      @encoding ||= @method_database.properties["encoding"]
    end

    def index_class(klass)
      add_class(klass)
      klass.entries.each do |entry|
        add_class_entry(klass, entry)
        add_spec(klass, entry)
      end
    end

    def index_document(document)
      source = entry_source(document)
      attributes = {
        :name => document.name,
        :local_name => document.title,
        :label => document.title,
        :type => "document",
        :document => source,
        :description => "#{document.title} #{source}",
        :version => version,
      }
      add_entry("#{version}:#{document.name}", attributes)
    end

    def index_library(library)
      source = entry_source(library)
      description = []
      [library.requires, library.classes, library.methods,
       library.sublibraries].each do |entries|
        entries.each do |entry|
          description << entry.name
        end
      end
      description << source
      library_name = library.name
      library_type = library.type_id.to_s
      attributes = {
        :name => library_name,
        :local_name => library_name,
        :label => library_name,
        :type => library_type,
        :document => source,
        :description => description.join(" "),
        :version => version,
      }
      add_entry("#{version}:#{library.name}", attributes)
      @database.libraries.add(library_name, :type => library_type)
    end

    def index_function(function)
      source = entry_source(function)
      attributes = {
        :name => function.name,
        :label => function.header,
        :local_name => function.name,
        :type => normalize_type_label(function.type_label),
        :version => version,
        :document => source,
        :signature => function.header,
        :description => source,
        :visibility => function.private? ? "private" : "public",
      }
      add_entry("#{version}:#{function.header}", attributes)
    end

    def add_class(klass)
      source = entry_source(klass)
      attributes = {
        :name => klass.name,
        :local_name => klass.name.split(/::/).last,
        :label => klass.name,
        :type => klass.type.to_s,
        :version => version,
        :document => source,
        :description => source,
      }
      library = klass.library
      attributes[:library] = library.name if library
      add_entry("#{version}:#{klass.name}", attributes)
      @database.specs.add(klass.name, :type => klass.type.to_s)
    end

    def add_class_entry(klass, entry)
      source = entry_source(entry)
      foreach_method_chunk(source) do |signatures, description|
        signatures.each do |signature|
          attributes = {
            :name => entry.spec_string,
            :label => "#{klass.name}#{entry.typemark}#{signature}",
            :local_name => signature.name,
            :type => normalize_type_label(entry.type_label),
            :version => version,
            :document => source,
            :signature => signature.to_s,
            :description => description,
            :visibility => entry.visibility.to_s,
          }
          klass_name = klass.name
          klass_type = normalize_type_label(klass.type.to_s)
          if klass.class?
            attributes[:class] = klass_name
            @database.classes.add(klass_name, :type => klass_type)
          elsif klass.module?
            attributes[:module] = klass_name
            @database.modules.add(klass_name, :type => klass_type)
          else
            attributes[:object] = klass_name
            @database.objects.add(klass_name, :type => klass_type)
          end
          library = entry.library
          attributes[:library] = library.name if library
          add_entry("#{version}:#{entry.spec_string}:#{signature}",
                    attributes)
        end
      end
    end

    def add_spec(klass, entry)
      @database.specs.add(entry.spec_string,
                          :type => normalize_type_label(entry.type_label))
    end

    def add_entry(key, attributes)
      attributes[:last_modified] = @base_time
      @database.entries.add(key, attributes)
    end

    def normalize_type_label(label)
      label.gsub(/ /, '-')
    end

    def foreach_method_chunk(source, &block)
      @screen ||= BitClust::TemplateScreen.new(:database => @method_database)
      @screen.send(:foreach_method_chunk, source, &block)
    end

    def entry_source(entry)
      source = entry.source
      if source.respond_to?(:force_encoding)
        source.force_encoding(@method_database.encoding)
      end
      source
    end
  end
end
