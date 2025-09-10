# frozen_string_literal: true

module ArticlesHelper
  # Render stored HTML safely with sensible defaults for headings, images, tables, etc.
  #
  # - Keeps authoring HTML (h1..h4, figure/figcaption, img width/height)
  # - Adds target/_blank & rel to external links
  # - Makes images responsive (max-width:100%; height:auto)
  # - Preserves width/height attributes if provided by the source
  # - De-duplicates identical <img> tags within the same <figure> (and consecutive duplicates globally)
  #
  def render_article_body(html)
    raw_html = html.to_s

    # 1) Sanitize with a relaxed, extended allowlist
    safe = sanitize(
      raw_html,
      tags: %w[
        p br a strong em b i u span ul ol li h1 h2 h3 h4 blockquote code pre
        figure figcaption img table thead tbody tr th td hr sup sub
      ],
      attributes: %w[
        href src alt title width height class id target rel colspan rowspan
        srcset sizes
      ]
    )

    # 2) Post-process with Nokogiri to add UX attributes/classes
    doc = Nokogiri::HTML::DocumentFragment.parse(safe)

    # External links: open in new tab, add security rel
    doc.css("a[href]").each do |a|
      href = a["href"].to_s
      next if href.start_with?("#") || href.start_with?("/") || (respond_to?(:request) && href.start_with?(request.base_url))

      a.set_attribute("target", "_blank")
      a.set_attribute("rel", "noopener noreferrer")
    end

    # Images: responsive, lazy, keep width/height if present
    doc.css("img").each do |img|
      img.set_attribute("loading", "lazy")
      img.set_attribute("decoding", "async")
      merged = (img["class"].to_s.split + %w[max-w-full h-auto rounded-2xl mx-auto]).uniq.join(" ")
      img.set_attribute("class", merged)
    end

    # *** De-duplicate identical images inside the same figure ***
    doc.css("figure").each do |fig|
      seen = {}
      fig.css("img").each do |img|
        key = img["src"].to_s.strip
        if key.empty?
          # If somehow only data-src exists (not expected post-sanitize), skip dedupe
          next
        end
        if seen[key]
          img.remove
        else
          seen[key] = true
        end
      end
    end

    # *** Optional: remove consecutive duplicate images globally (outside figures) ***
    prev_src = nil
    doc.css("img").to_a.each do |img|
      src = img["src"].to_s.strip
      if src.present? && src == prev_src
        img.remove
      else
        prev_src = src
      end
    end

    # Headings: add some rhythm
    doc.css("h1,h2,h3,h4").each do |h|
      merged = (h["class"].to_s.split + %w[font-bold mt-8 mb-4]).uniq.join(" ")
      h.set_attribute("class", merged)
    end

    # Tables: make them scrollable horizontally on small screens
    doc.css("table").each do |table|
      wrapper = Nokogiri::XML::Node.new("div", doc)
      wrapper["class"] = "overflow-x-auto my-6"
      table.replace(wrapper)
      wrapper.add_child(table)
      table["class"] = [ table["class"], "min-w-full border-collapse" ].compact.join(" ")
    end

    # Return HTML safe
    doc.to_html.html_safe
  end
end
