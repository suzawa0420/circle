# Emit source locations only: never include exception messages or response bodies.
module CiFailureLocations
  def run
    result = super
    if ENV['CI'] == 'true' && !result.passed?
      result.failures.each do |failure|
        frame = failure.backtrace.find { |entry| entry.match?(%r{/test/[A-Za-z0-9_./-]+\.rb:\d+}) }
        next unless frame
        match = frame.match(%r{/(test/[A-Za-z0-9_./-]+\.rb):(\d+)})
        next unless match
        label = "#{self.class.name}##{name} (#{failure.class.name})"
        label = label.gsub('%', '%25').gsub("\r", '%0D').gsub("\n", '%0A')
        puts "::error file=#{match[1]},line=#{match[2]}::#{label}"
      end
    end
    result
  end
end
Minitest::Test.prepend(CiFailureLocations)
