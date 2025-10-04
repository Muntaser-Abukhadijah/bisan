# frozen_string_literal: true

module ArticlesHelper
  def render_article_body(html)
    raw_html = html.to_s

    # ---------- 0) PRE-PROCESS ----------
    doc0 = Nokogiri::HTML::DocumentFragment.parse(raw_html)

    # Remove <noscript> entirely (WP/Jetpack duplicates live here)
    doc0.css("noscript").remove

    # Kill explicit lazy fallbacks if present
    doc0.css("img[data-lazy-fallback]").each(&:remove)

    # Promote lazy attrs and clean up placeholder srcset
    doc0.css("img").each do |img|
      if (lazy = img["data-lazy-src"] || img["data-src"]).present?
        img["src"] = lazy
        img.remove_attribute("data-lazy-src")
        img.remove_attribute("data-src")
      end
      if (lazyset = img["data-lazy-srcset"] || img["data-srcset"]).present?
        img["srcset"] = lazyset
        img.remove_attribute("data-lazy-srcset")
        img.remove_attribute("data-srcset")
      end
      img.remove_attribute("srcset") if img["srcset"]&.start_with?("data:")

      # If src missing but srcset exists, take first candidate
      if img["src"].to_s.strip.empty? && img["srcset"].present?
        first = img["srcset"].split(",").first.to_s.strip.split(/\s+/).first
        img["src"] = first if first.present?
      end

      # Strip query/fragment from src to avoid dupes like ?is-pending-load=1
      if (src = img["src"]).present?
        begin
          u = URI.parse(src)
          u.query = u.fragment = nil
          img["src"] = u.to_s
        rescue
          img["src"] = src.to_s.split("?").first
        end
      end
    end

    prepped_html = doc0.to_html

    # ---------- 1) SANITIZE ----------
    safe = sanitize(
      prepped_html,
      tags: %w[
        p br a strong em b i u span ul ol li h1 h2 h3 h4 blockquote code pre
        figure figcaption img table thead tbody tr th td hr sup sub
      ],
      attributes: %w[
        href src alt title width height class id target rel colspan rowspan
        srcset sizes referrerpolicy
      ]
    )

    # ---------- 2) POST-PROCESS ----------
    doc = Nokogiri::HTML::DocumentFragment.parse(safe)

    # External links → new tab + rel
    doc.css("a[href]").each do |a|
      href = a["href"].to_s
      next if href.start_with?("#", "/") || (respond_to?(:request) && href.start_with?(request.base_url))
      a["target"] = "_blank"
      a["rel"]    = "noopener noreferrer"
    end

    # Images: responsive, async, safe referrer
    doc.css("img").each do |img|
      img.remove_attribute("srcset") if img["srcset"]&.start_with?("data:")
      img["loading"]         = "lazy"
      img["decoding"]        = "async"
      img["referrerpolicy"] ||= "no-referrer"
      merged = (img["class"].to_s.split + %w[max-w-full h-auto rounded-2xl mx-auto]).uniq.join(" ")
      img["class"] = merged
    end

    # Helper to normalize URLs for dedupe (drop query/frag, decode %XX, fold www.)
    normalize_url = ->(url) do
      return "" if url.blank?
      begin
        u = URI.parse(url)
        host = u.host.to_s.downcase.sub(/\Awww\./, "")
        path = (CGI.unescape(u.path.to_s) rescue u.path.to_s)
        "#{u.scheme}://#{host}#{path}"
      rescue
        url.to_s.split("?").first
      end
    end

    # De-duplicate identical images within the same figure
    doc.css("figure").each do |fig|
      seen = {}
      fig.css("img").each do |img|
        key = normalize_url.call(img["src"])
        next if key.blank?
        seen[key] ? img.remove : seen[key] = true
      end
    end

    # De-duplicate consecutive images globally
    prev_key = nil
    doc.css("img").to_a.each do |img|
      key = normalize_url.call(img["src"])
      if key.present? && key == prev_key
        img.remove
      else
        prev_key = key
      end
    end

    # Headings rhythm
    doc.css("h1,h2,h3,h4").each do |h|
      merged = (h["class"].to_s.split + %w[font-bold mt-8 mb-4]).uniq.join(" ")
      h["class"] = merged
    end

    # Tables: wrap for horizontal scroll
    doc.css("table").each do |table|
      wrapper = Nokogiri::XML::Node.new("div", doc)
      wrapper["class"] = "overflow-x-auto my-6"
      table.replace(wrapper)
      wrapper.add_child(table)
      table["class"] = [ table["class"], "min-w-full border-collapse" ].compact.join(" ")
    end

    doc.to_html.html_safe
  end
end
