# frozen_string_literal: true

require "test_helper"

class ClipArticleExtractorTest < ActiveSupport::TestCase
  test "extracts the largest article and removes page chrome" do
    html = <<~HTML
      <!doctype html>
      <html>
        <body>
          <header>Site header</header>
          <nav>Navigation</nav>
          <article><h1>Article</h1><p>Main content with useful details.</p></article>
          <aside>Advertisement</aside>
          <script>alert("x")</script>
        </body>
      </html>
    HTML

    extracted = ClipArticleExtractor.extract(html)

    assert_includes extracted, "Main content"
    assert_not_includes extracted, "Site header"
    assert_not_includes extracted, "Navigation"
    assert_not_includes extracted, "Advertisement"
    assert_not_includes extracted, "<script"
  end

  test "falls back to body when article and main are absent" do
    extracted = ClipArticleExtractor.extract("<html><body><div>Fallback body</div></body></html>")

    assert_includes extracted, "Fallback body"
  end
end
