require "test_helper"

# Browser tests through Playwright. Classes run in desktop Chromium unless they call
# driven_by_desktop, driven_by_phone, or driven_by_desktop_without_javascript. Rails saves
# a screenshot to tmp/screenshots when a test fails.
#
# Broadcasts reach the browser through the test cable adapter: it records them for
# assert_broadcasts and also delivers them in-process, like the async adapter, to the test
# server's subscribers. Jobs use the test queue adapter, so tests call answer_questions to
# run AskJob in the test process with the fake embedder and answerer.
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include TestData
  include ActiveJob::TestHelper
  include FakeAnswerer::TestHelper
  include CitedAnswerScenario

  # The CLI and its browsers come with the dev container (CI sets PLAYWRIGHT_CLI). Without
  # a path the driver runs npx, which downloads.
  PLAYWRIGHT = { playwright_cli_executable_path: ENV.fetch("PLAYWRIGHT_CLI", "playwright"), headless: true }.freeze
  DESKTOP = [ 1280, 900 ].freeze
  # Names from Playwright's device list.
  PHONE = "iPhone 15"
  SMALL_PHONE = "iPhone SE"
  ANDROID_PHONE = "Pixel 7"

  # Find controls by their accessible names, like the "Source 1" markers.
  Capybara.enable_aria_label = true

  def self.driven_by_desktop(browser: :chromium)
    driven_by :playwright, screen_size: DESKTOP, options: { name: :"desktop_#{browser}", browser_type: browser, **PLAYWRIGHT }
  end

  # A Playwright device profile, for viewport, touch, and user agent, in WebKit unless
  # browser says otherwise. reduced_motion makes the page prefer reduced motion.
  def self.driven_by_phone(device = PHONE, browser: :webkit, reduced_motion: false)
    profile = playwright_device(device)
    profile = profile.merge(reducedMotion: "reduce") if reduced_motion
    name = [ device.parameterize(separator: "_"), browser, ("reduced_motion" if reduced_motion) ].compact.join("_")
    driven_by :playwright, screen_size: profile[:viewport].values_at(:width, :height),
              options: { name: name.to_sym, browser_type: browser, **profile, **PLAYWRIGHT }
  end

  driven_by_desktop

  def self.driven_by_desktop_without_javascript
    driven_by :playwright, screen_size: DESKTOP,
              options: { name: :desktop_without_javascript, browser_type: :chromium, javaScriptEnabled: false, **PLAYWRIGHT }
  end

  # Device profiles come from the CLI, so this starts it once, briefly.
  def self.playwright_device(name)
    Playwright.create(playwright_cli_executable_path: PLAYWRIGHT[:playwright_cli_executable_path]) { it.devices.fetch(name) }
  end

  # Only localhost, for Capybara's checks on its test server. Everything else stays blocked.
  setup do
    WebMock.disable_net_connect!(allow_localhost: true)
    VCR.configuration.ignore_localhost = true
  end

  teardown do
    VCR.configuration.ignore_localhost = false
    WebMock.disable_net_connect!
  end

  setup do
    Rails.configuration.x.ask_page[:rate_limit_store].clear
    ChunkEmbedding.create!(chunk: chunks(:leave), model: "voyage-4-lite", strategy: :raw, dimensions: 1024,
                           embedding: FakeEmbedder.new.vector_for("leave"), input_hash: "abc")
  end

  private
    def ask(text)
      visit root_path
      fill_in "Your question", with: text
      click_on "Ask"
      assert_selector "h1", text: text
    end

    # Runs AskJob for the questions asked so far, without the network.
    def answer_questions(answerer = FakeAnswerer.new)
      with_fake_embedder { with_fake_answerer(answerer) { perform_enqueued_jobs(only: AskJob) } }
    end

    # The page's stream subscription is confirmed, so later broadcasts will reach it.
    def assert_subscribed_to_answer
      assert_selector "turbo-cable-stream-source[connected]", visible: :all
    end
end
