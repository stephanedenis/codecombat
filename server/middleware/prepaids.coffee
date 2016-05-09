wrap = require 'co-express'
errors = require '../commons/errors'
database = require '../commons/database'
Prepaid = require '../models/Prepaid'
User = require '../models/User'

module.exports =
  logError: (user, msg) ->
    console.warn "Prepaid Error: [#{user.get('slug')} (#{user._id})] '#{msg}'"
    
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

  redeem: wrap (req, res) ->
    if not req.user?.isTeacher()
      throw new errors.Forbidden('Must be a teacher to use enrollments')
    
    prepaid = yield database.getDocFromHandle(req, Prepaid)
    if not prepaid
      throw new errors.NotFound('Prepaid not found.')
      
    cutoff = new Date(2015,11,11)
    if prepaid._id.getTimestamp().getTime() < cutoff.getTime()
      throw new errors.Forbidden('Cannot redeem from prepaids older than November 11, 2015')
    unless prepaid.get('creator').equals(req.user._id)
      throw new errors.Forbidden('You may not redeem enrollments from this prepaid')
    if prepaid.get('redeemers')? and _.size(prepaid.get('redeemers')) >= prepaid.get('maxRedeemers')
      throw new errors.Forbidden('This prepaid is exhausted')
    unless prepaid.get('type') is 'course'
      throw new errors.Forbidden('This prepaid is not of type "course"')
    if prepaid.get('endDate') and new Date(prepaid.get('endDate')) < new Date()
      throw new errors.Forbidden('This prepaid is expired')

    user = yield User.findById(req.body?.userID)
    if not user
      throw new errors.NotFound('User not found.')

    if user.get('coursePrepaid')?._id
      return res.status(200).send(prepaid.toObject({req: req}))
    if user.isTeacher()
      throw new errors.Forbidden('Teachers may not be enrolled')
    
    query =
      _id: prepaid._id
      'redeemers.userID': { $ne: user._id }
      $where: "this.maxRedeemers > 0 && (!this.redeemers || this.redeemers.length < #{prepaid.get('maxRedeemers')})"
    update = { $push: { redeemers : { date: new Date(), userID: user._id } }}
    result = yield Prepaid.update(query, update)
    if result.nModified is 0
      @logError(req.user, "POST prepaid redeemer lost race on maxRedeemers")
      throw new errors.Forbidden('This prepaid is exhausted')
    
    update = {
      $set: {
        coursePrepaid: {
          _id: prepaid._id
          startDate: prepaid.get('startDate')
          endDate: prepaid.get('endDate')
        }
      }
    }
    if not user.get('role')
      update.$set.role = 'student'
    yield user.update(update)
    
    # return prepaid with new redeemer added locally
    redeemers = _.clone(prepaid.get('redeemers') or [])
    redeemers.push({ date: new Date(), userID: user._id })
    prepaid.set('redeemers', redeemers)
    res.status(201).send(prepaid.toObject({req: req}))
