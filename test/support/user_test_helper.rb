# Users for tests that sign in. The password meets User's 12-character minimum.
module UserTestHelper
  PASSWORD = "correct horse battery"

  def create_user(email_address = "owner@example.com", password: PASSWORD)
    User.create!(email_address: email_address, password: password)
  end
end
