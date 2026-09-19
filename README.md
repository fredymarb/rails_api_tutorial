# Rails Devise JWT API

An API-only Rails template with Devise authentication, JWT access tokens, and token revocation through a denylist.

## Stack

- Ruby 3.3.4
- Rails 8.1
- PostgreSQL
- Devise and Devise JWT
- JSON:API Serializer
- Rack CORS

## Requirements

- Ruby 3.3.4
- Bundler
- PostgreSQL

The project pins `json` below version 3 because Rails 8.1.3.1 is incompatible with `json 3.0.2` when parsing JSON request bodies.

## Setup

```bash
git clone <repository-url>
cd rails_api_tutorial
bundle install
bin/rails credentials:edit
bin/rails db:prepare
```

Create or configure the PostgreSQL database in `config/database.yml` if your local PostgreSQL settings differ from the defaults.

In the credentials editor, add a long, randomly generated JWT secret:

```yaml
devise:
  jwt_secret_key: your-long-random-secret
```

Rails reads this value when it boots. Keep production credentials out of version control. The access tokens issued by this application expire after 30 minutes.

## Run the API

```bash
bin/rails server -p 3000
```

The API is available at `http://localhost:3000`.

Check the health endpoint:

```bash
curl http://localhost:3000/up
```

If port 3000 is already in use, run the server on another port, such as `3001`.

## Authentication API

Signup and login are separate actions. Signup creates the user but does not issue a token. Login returns a JWT in the `Authorization` response header.

| Method   | Path      | Authentication | Success response                                                        |
| -------- | --------- | -------------- | ----------------------------------------------------------------------- |
| `POST`   | `/signup` | None           | `200 OK` with the new user's attributes                                 |
| `POST`   | `/login`  | None           | `200 OK` with user attributes and an `Authorization: Bearer ...` header |
| `DELETE` | `/logout` | Bearer JWT     | `200 OK` and a confirmation message                                     |

### Signup

```bash
curl -X POST http://localhost:3000/signup \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{"user":{"email":"james@example.com","password":"Password123","password_confirmation":"Password123"}}'
```

A successful signup returns the user attributes and `Signed up successfully.`. It does not include an `Authorization` header.

### Login

```bash
curl -i -X POST http://localhost:3000/login \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{"user":{"email":"james@example.com","password":"Password123"}}'
```

Copy the `Authorization: Bearer ...` response header from login.

Invalid signup data returns `422 Unprocessable Entity`. Invalid login credentials use Devise's unauthenticated response.

### Logout

```bash
curl -X DELETE http://localhost:3000/logout \
  -H "Accept: application/json" \
  -H "Authorization: Bearer YOUR_JWT_HERE"
```

Logout revokes the token by adding it to the JWT denylist.

An absent, invalid, or revoked token returns `401 Unauthorized`.

### Denylist maintenance

Expired denylist entries are removed automatically by Solid Queue in production. The recurring task in `config/recurring.yml` runs `JwtDenylist.expired.delete_all` every day at 5:00 AM. It is configured as a recurring command rather than an `ActiveJob` class.

## Postman

For signup and login, use `POST` with a raw JSON body and these headers:

```text
Content-Type: application/json
Accept: application/json
```

For logout, use `DELETE` and set the Authorization type to **Bearer Token**. Paste the token returned by login.

## CORS

Development CORS currently accepts requests from every origin and exposes the `Authorization` response header so browser clients can read the JWT. Before deploying, replace the wildcard origin in `config/initializers/cors.rb` with the URL of the frontend application.

## Development checks

```bash
bin/rubocop
bin/rails test
bin/rails zeitwerk:check
bin/brakeman --quiet --no-pager
```

## Documentation

See [DEVISE_JWT_API.md](DEVISE_JWT_API.md) for implementation details, troubleshooting history, and fixes for API-only Devise sessions, JSON parsing, port conflicts, and Rails 8 compatibility.
