wrap = require 'co-express'
errors = require '../commons/errors'
database = require '../commons/database'
Prepaid = require '../models/Prepaid'
User = require '../models/User'

module.exports =
  post: wrap (req, res) ->
    validTypes = ['course']
    unless req.body.type in validTypes
      throw new errors.UnprocessableEntity("type must be on of: #{validTypes}.")
      # TODO: deprecate or refactor other prepaid types
    
    if req.body.creator
      user = yield User.search(req.body.creator)
      if not user
        throw new errors.NotFound('User not found')
      req.body.creator = user.id

    prepaid = database.initDoc(req, Prepaid)
    database.assignBody(req, prepaid)
    prepaid.set('code', yield Prepaid.generateNewCodeAsync())
    prepaid.set('redeemers', [])
    database.validateDoc(prepaid)
    yield prepaid.save()
    res.status(201).send(prepaid.toObject())
