# Devise JWT API

This document describes how the Rails API authentication flow was created, the problems encountered, and the fixes that made it work.

## Stack

- Rails 8.1 API-only application
- PostgreSQL
- Devise for user authentication
- Devise JWT for JSON Web Tokens
- `jsonapi-serializer` for user responses
- `rack-cors` for frontend requests
- `JwtDenylist` for token revocation on logout

## Dependencies

The relevant entries in `Gemfile` are:

```ruby
gem "rails", "~> 8.1.3", ">= 8.1.3.1"
gem "json", "< 3"
gem "devise"
gem "devise-jwt"
gem "jsonapi-serializer"
gem "rack-cors"
```

Run:

```bash
bundle install
bin/rails db:migrate
```

The `json` constraint is important. Rails 8.1 calls `JSON.parse` with an options argument, but `json 3.0.2` rejects that call. Without the constraint, every `application/json` request can fail before the controller runs with:

```text
ActionDispatch::Http::Parameters::ParseError
wrong number of arguments (given 2, expected 1)
```

The working version in this project is `json 2.21.2`.

## User and JWT denylist models

The user enables normal Devise modules plus JWT authentication:

```ruby
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :jwt_authenticatable, jwt_revocation_strategy: JwtDenylist
end
```

The denylist model includes Devise JWT's built-in strategy:

```ruby
class JwtDenylist < ApplicationRecord
  include Devise::JWT::RevocationStrategies::Denylist

  self.table_name = "jwt_denylist"
end
```

The denylist migration creates storage for a token's JWT ID and expiration time. On logout, the token is inserted into this table and cannot be used again.

## Routes

`config/routes.rb` maps Devise endpoints to API-friendly paths and custom controllers:

```ruby
devise_for :users, path: "", path_names: {
  sign_in: "login",
  sign_out: "logout",
  registration: "signup"
}, controllers: {
  sessions: "users/sessions",
  registrations: "users/registrations"
}
```

The resulting endpoints are:

| Method | Path      | Purpose                             |
| ------ | --------- | ----------------------------------- |
| POST   | `/signup` | Create a user                       |
| POST   | `/login`  | Authenticate a user and issue a JWT |
| DELETE | `/logout` | Revoke the current JWT              |
| GET    | `/up`     | Check that Rails is healthy         |

## API-only Devise configuration

API-only Rails applications do not include browser sessions. Devise normally tries to store the authenticated user in a session, which causes:

```text
ActionDispatch::Request::Session::DisabledSessionError
Your application has sessions disabled.
```

The fix in `config/initializers/devise.rb` is:

```ruby
config.skip_session_storage = [ :http_auth, :params_auth ]
```

Registration normally automatically signs the new user in. This API keeps signup and login as separate actions, so the custom registrations controller overrides that hook without signing the user in:

```ruby
def sign_up(_resource_name, _resource)
end
```

Signup creates the account but does not issue a JWT. The user must call `POST /login` separately to authenticate.

After changing an initializer or `Gemfile`, restart Rails.

## JSON controllers

The custom controllers return JSON instead of redirects or HTML.

The registration controller returns serialized user data after signup. The sessions controller returns serialized user data after login and a status message after logout.

Devise 5 changed the logout hook signature to accept a keyword argument. The compatible override is:

```ruby
def respond_to_on_destroy(non_navigational_status: :no_content)
  # JSON response implementation
end
```

Using the old zero-argument method causes:

```text
ArgumentError: wrong number of arguments (given 1, expected 0)
```

## CORS and the JWT header

`config/initializers/cors.rb` allows frontend requests and exposes the response `Authorization` header:

```ruby
resource "*",
  headers: :any,
  expose: [ "Authorization" ],
  methods: [ :get, :post, :put, :patch, :delete, :options, :head ]
```

For production, replace `origins "*"` with the actual frontend origin.

## Run the API

From the application directory:

```bash
cd rails_api_tutorial
bin/rails server -p 3000
```

If port 3000 is already occupied, use another port:

```bash
bin/rails server -p 3001
```

A stale PID file or another Puma process can also prevent startup. Check the process that owns the port before stopping it:

```bash
ss -ltnp 'sport = :3000'
```

## Test with curl

### Signup

```bash
curl -X POST http://localhost:3000/signup \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{"user":{"email":"james@example.com","password":"Password123","password_confirmation":"Password123"}}'
```

Expected status: `200 OK` with a `Signed up successfully.` message and no JWT.

### Login

The JWT is returned in the response `Authorization` header.

```bash
curl -i -X POST http://localhost:3000/login \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{"user":{"email":"james@example.com","password":"Password123"}}'
```

Expected status: `200 OK`. Save the value of the `Authorization` header, including its `Bearer` prefix.

### Logout

Send the login token in the `Authorization` header:

```bash
curl -X DELETE http://localhost:3000/logout \
  -H "Accept: application/json" \
  -H "Authorization: Bearer YOUR_JWT_HERE"
```

Expected status: `200 OK` with a message indicating that the user was logged out. The token is added to `jwt_denylist`.

## Test with Postman

For signup and login:

1. Choose `POST`.
2. Use `http://localhost:3000/signup` or `http://localhost:3000/login`.
3. Set `Content-Type: application/json` and `Accept: application/json`.
4. Select Body -> raw -> JSON.
5. Send the nested `user` object shown in the curl examples.

For logout:

1. Choose `DELETE` and use `http://localhost:3000/logout`.
2. Open Authorization.
3. Select Bearer Token.
4. Paste the JWT returned by login.

Do not paste Markdown backticks into the request body, and do not manually set `Content-Length`.

## Problems and fixes

### 1. Signup automatically logged the user in

Devise's default registration flow signs a newly created user in. That is not desirable for this API because signup and login are separate user actions.

Fix: override `sign_up` with an empty hook in `Users::RegistrationsController`. Login remains responsible for issuing the JWT.

### 2. Rails started the wrong command

Running `rails s` from `/home/nat/app` made Rails treat `s` as an application-generation argument because the shell was not inside the Rails application.

Fix:

```bash
cd /home/nat/app/rails_api_tutorial
bin/rails server
```

### 3. Port 3000 was already in use

Puma reported:

```text
Address already in use - bind(2) for "127.0.0.1" port 3000
```

Fix: identify the process with `ss -ltnp 'sport = :3000'`, then either stop the correct process or run the API on another port. Do not kill an unrelated application just to reclaim the port.

### 4. JSON requests returned HTTP 400

The JSON payload was valid, but Rails 8.1.3.1 was paired with `json 3.0.2`. Rails called `JSON.parse` with two arguments and the installed gem accepted only one.

Fix:

```ruby
gem "json", "< 3"
```

Then run `bundle update json` and restart Rails.

### 5. Authentication returned `DisabledSessionError`

Devise attempted to write authentication data to a Rails session. API-only Rails has sessions disabled.

Fix the API-wide session behavior with:

```ruby
config.skip_session_storage = [ :http_auth, :params_auth ]
```

Because signup and login are separate actions, prevent registration from signing the new user in at all:

```ruby
def sign_up(_resource_name, _resource)
end
end

The old `sign_in(..., store: false)` workaround is no longer used. `store: false` prevents a Rails session write, but it still performs a sign-in lifecycle step and can issue a JWT.
```

### 6. Logout returned an argument error

Devise 5 invokes `respond_to_on_destroy` with `non_navigational_status:`. The custom controller originally defined a zero-argument method.

Fix:

```ruby
def respond_to_on_destroy(non_navigational_status: :no_content)
```

### 7. Test accounts remained in the database

End-to-end tests created temporary users. Remove test accounts after testing, or use a dedicated test database. For a local development account:

```bash
bin/rails runner "User.find_by(email: 'james@example.com')&.destroy"
```

## Verification checklist

- `GET /up` returns `200`.
- Signup returns `200`, creates a user, and does not include an `Authorization` response header.
- Login returns `200` and includes an `Authorization: Bearer ...` response header.
- Logout with that token returns `200`.
- The logout token is written to `jwt_denylist`.
- A fresh Rails restart succeeds after dependency or initializer changes.
- `bundle check` reports that all dependencies are satisfied.
