require 'crass'
require 'set'

# Compile the shared styles once, then discard rules for unrelated screens.
# Template/helper/JS dependencies keep the asset digest in sync with navigation,
# conditional markup and pagination as well as the stylesheet itself.
class PublicListingStyles
  SOURCE_GLOBS = %w[
    app/views/layouts/* app/views/circles/commons/*
    app/views/circles/circles/index* app/views/circles/search/*
    app/views/circles/events/**/*.haml app/views/circles/prefectures/**/*.haml
    app/views/circles/tags/**/*.haml app/views/tags/*.haml
    app/views/users/_users_list* app/helpers/* app/assets/javascripts/mobile_navigation.js
  ].freeze
  # Kaminari generates these classes outside application templates.
  GENERATED_CLASSES = %w[pagination page current gap next prev first last disabled
    active open hidden collapse in dropdown-menu dropdown-toggle].freeze

  def self.call(input)
    return { data: input[:data] } unless input[:name] == 'public_listing'

    context = input[:environment].context_class.new(input)
    root = Rails.root
    files = SOURCE_GLOBS.flat_map { |glob| Dir[root.join(glob)] }.select { |path| File.file?(path) }.sort
    files.each { |path| context.depend_on(path) }
    %w[app/views/circles app/views/layouts app/views/tags app/views/users app/helpers app/assets/javascripts].each do |directory|
      ([root.join(directory).to_s] + Dir[root.join(directory, '**/')]).uniq.each { |path| context.depend_on(path) }
    end
    context.depend_on(__FILE__)
    words = files.flat_map { |path| File.read(path).scan(/[A-Za-z_][A-Za-z0-9_-]*/) }.to_set
    words.merge(GENERATED_CLASSES)
    context.metadata.merge(data: filter(input[:data], words))
  end

  def self.filter(css, classes)
    Crass.parse(css).filter_map do |node|
      case node[:node]
      when :style_rule
        # Keep a grouped rule when any selector is used, preserving alias rules
        # and commas inside :not()/attribute selectors without splitting them.
        selectors = node[:selector][:value].split(/,(?![^\[\(]*[\]\)])/)
        next unless selectors.any? { |selector| selector.scan(/\.([A-Za-z_][A-Za-z0-9_-]*)/).flatten.all? { |name| classes.include?(name) } }
        "#{node[:selector][:value]}{#{Crass::Parser.stringify(node[:children].flat_map { |child| (child[:tokens] || []) + [{ raw: ';' }] })}}"
      when :at_rule
        prelude = Crass::Parser.stringify(node[:prelude])
        if %w[media supports layer container].include?(node[:name]) && node[:block]
          body = filter(Crass::Parser.stringify(node[:block]), classes)
          "@#{node[:name]} #{prelude}{#{body}}" unless body.empty?
        else
          Crass::Parser.stringify(node[:tokens])
        end
      end
    end.join
  end
end
