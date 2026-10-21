class ColumnImageUploader < ImageUploader
  # Keep the shared storage, orientation and legacy URL behavior, but retain
  # enough pixels for an article cover instead of the shared 400px thumbnail.
  self.processors = processors.map do |processor|
    processor.first == :resize_to_limit ? [:resize_to_limit, [1600, 1600], nil, nil] : processor
  end

  def extension_allowlist
    %w[jpg jpeg png]
  end

  def content_type_allowlist
    %r{\Aimage/(jpeg|png)\z}
  end
end
