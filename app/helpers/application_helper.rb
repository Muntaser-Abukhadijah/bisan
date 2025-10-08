module ApplicationHelper
  include Pagy::Frontend
  include Heroicon::Engine.helpers

  RTL_LOCALES = %i[ar].freeze
  def page_dir(locale = I18n.locale)
    RTL_LOCALES.include?(locale.to_sym) ? "rtl" : "ltr"
  end
end
