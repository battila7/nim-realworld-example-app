import asyncdispatch, json, httpcore, tables, pegs

import rosencrantz

from ../model/user import User
from ../service/userservice import login
from ../service/authservice import issueToken
from filter/auth import mandatoryAuth
from filter/terminal import unprocessableEntity
from filter/validation import validateBody

let
  emailPattern    = peg"""^\S+@\S+\.\S+$"""
  usernamePattern = peg"""^[a-zA-Z0-9]+$"""

proc loggedInUser(user: User): Handler =
  let resultJson = %*{
    "email": user.email,
    "token": issueToken(user.id),
    "username": user.username,
    "image": user.image,
    "bio": user.bio
  }

  ok(resultJson)

proc authValidator(body: JsonNode): Table[string, string] {.procvar.} =
  result = initTable[string, string]()

  if not body.hasKey("user"):
    result.add("user", "missing field")
    return

  if not body["user"].hasKey("email"):
    result.add("email", "can't be blank")
  if not body["user"].hasKey("password"):
    result.add("password", "can't be blank")

# A nice JSON validator framework should be written instead of
# this horrible code.
proc registerValidator(body: JsonNode): Table[string, string] {.procvar.} =
  result = initTable[string, string]()

  if not body.hasKey("user"):
    result.add("user", "missing field")
    return

  if not body["user"].hasKey("email"):
    result.add("email", "can't be blank")
  elif not (body["user"]["email"].str =~ emailPattern):
    result.add("email", "is invalid")

  if not body["user"].hasKey("username"):
    result.add("username", "can't be blank")
  elif not (body["user"]["username"].str =~ usernamePattern):
    result.add("username", "is invalid")

  if not body["user"].hasKey("password"):
    result.add("password", "can't be blank")

let
  authentication =
    post ->
      path("/api/users/login") ->
        jsonBody do (body: JsonNode) -> auto:
          validateBody(authValidator, body) do -> auto:
            scopeAsync do:
              let
                email = body["user"]["email"].str
                password = body["user"]["password"].str

              let (success, user) = await login(email, password)

              if not success:
                let errors = {"email or password" : "is invalid"}.toTable()

                return unprocessableEntity(errors)
              else:
                return loggedInUser(user)

  registration =
    post ->
      path("/api/users") ->
        jsonBody do (body: JsonNode) -> auto:
          validateBody(registerValidator, body) do -> auto:
            scopeAsync do:
              let
                email = body["user"]["email"].str
                username = body["user"]["username"].str
                password = body["user"]["password"].str

              return ok("Registration")

  getCurrentUser =
    get ->
      path("/api/user") ->
        mandatoryAuth do (user: User) -> auto:
          return loggedInUser(user)

  updateUser =
    put ->
      path("/api/user") ->
        mandatoryAuth do (user: User) -> auto:
          ok("Update user")

let handler* =
  authentication ~
  registration ~
  getCurrentUser ~
  updateUser
