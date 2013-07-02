# Be sure to restart your server when you modify this file.

# Your secret key is used for verifying the integrity of signed cookies.
# If you change this key, all old signed cookies will become invalid!

# Make sure the secret is at least 30 characters and all random,
# no regular words or you'll be exposed to dictionary attacks.
# You can use `rake secret` to generate a secure secret key.

# Make sure your secret_key_base is kept private
# if you're sharing your code publicly.


Openblight::Application.config.secret_token = ENV['SECRET_TOKEN'] || '592921b99944819ea2758b5df143e4ce8ac14d3bcb77c52a2f41d41f24ed1f7eed209f44e3ae18116e9424aaf430a1ba7ebb2bb644bb9964545a19ee71a52f4e'