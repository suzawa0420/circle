class ColumnImageUploader < ImageUploader
  # Article covers share the 1200px detail-photo processing and legacy URLs.

  def extension_allowlist
    %w[jpg jpeg png]
  end

  def content_type_allowlist
    %r{\Aimage/(jpeg|png)\z}
  end
end
