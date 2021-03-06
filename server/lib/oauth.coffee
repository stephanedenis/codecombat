co = require 'co'
OAuthProvider = require '../models/OAuthProvider'
database = require '../commons/database'
errors = require '../commons/errors'

getIdentityFromOAuth = co.wrap ({providerId, accessToken, code}) ->
  unless providerId and (accessToken or code)
    throw new errors.UnprocessableEntity('Properties "provider" and "accessToken" or "code" required.')

  if not database.isID(providerId)
    throw new errors.UnprocessableEntity('"provider" is not a valid id')

  provider = yield OAuthProvider.findById(providerId)
  if not provider
    throw new errors.NotFound('Provider not found.')

  if code and not accessToken
    { access_token: accessToken } = yield provider.getTokenWithCode(code)
    if not accessToken
      throw new errors.UnprocessableEntity('Code lookup failed')

  userData = yield provider.lookupAccessToken(accessToken)
  if not userData
    throw new errors.UnprocessableEntity('User lookup failed')

  identity = {
    provider: provider._id
    id: userData.id
  }

  return identity

  
module.exports = {
  getIdentityFromOAuth
}
