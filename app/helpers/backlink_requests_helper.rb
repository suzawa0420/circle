module BacklinkRequestsHelper
  def backlink_destination(circle)
    "https://circle-book.com#{circle_path(circle)}"
  end

  def backlink_embed_code(circle, banner: false)
    label = banner ? '<img src="https://circle-book.com/images/logo.png" alt="サークルブック" width="240" style="max-width:100%;height:auto;">' : ERB::Util.html_escape("#{circle.name}｜サークルブック")
    %(<a href="#{ERB::Util.html_escape(backlink_destination(circle))}" target="_blank" rel="noopener">#{label}</a>)
  end
end
