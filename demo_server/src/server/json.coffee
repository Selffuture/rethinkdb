goog.provide('rethinkdb.server.RDBJson')

class RDBJson
    abstract = new Error "Abstract method"

    isNull: -> (@ instanceof RDBPrimitive and @asJSON() is null)

    asJSON: -> throw abstract
    copy: -> throw abstract

    not: -> throw abstract

    eq: (other) -> throw abstract
    ne: (other) -> not @eq other
    lt: (other) -> throw abstract
    le: (other) -> throw abstract
    gt: (other) -> throw abstract
    ge: (other) -> throw abstract

    add: (other) -> throw abstract
    sub: (other) -> throw abstract
    mul: (other) -> throw abstract
    div: (other) -> throw abstract
    mod: (other) -> throw abstract

# Kind of a psudo class, it only supports one static method that mixes in selection functionality
class RDBSelection
    makeSelection: (obj, table) ->
        proto =
            update: (mapping) ->
                try
                    update_doc = mapping @
                catch err
                    if err instanceof MissingAttribute
                        return {errors: 1, error: "Object:\n#{DemoServer.prototype.convertToJSON(err.object)}\nis missing attribute #{DemoServer.prototype.convertToJSON(err.attribute)}"}
                    else # Can it happen?
                        throw err
                if update_doc[table.primaryKey]? and update_doc[table.primaryKey].asJSON() isnt @[table.primaryKey].asJSON()
                    return {errors: 1, error: "update cannot change primary key #{table.primaryKey} (got objects #{DemoServer.prototype.convertToJSON(@.asJSON())}, #{DemoServer.prototype.convertToJSON(update_doc.asJSON())})"}
                neu = @.merge mapping @
                table.insert neu, true
                {updated: 1}

            replace: (mapping) ->
                update_doc = mapping @
                if update_doc.asJSON()[table.primaryKey] isnt @asJSON()[table.primaryKey]
                    return {errors: 1, error: "mutate cannot change primary key #{table.primaryKey} (got objects #{DemoServer.prototype.convertToJSON(@.asJSON())}, #{DemoServer.prototype.convertToJSON(update_doc.asJSON())})"}

                neu = update_doc
                table.insert neu, true
                {modified: 1}

            del: ->
                table.deleteKey @[table.primaryKey].asJSON()
                {deleted: 1}

        proto.__proto__ = obj.__proto__
        obj.__proto__ = proto

        return obj

class RDBPrimitive extends RDBJson
    constructor: (val) -> @data = val
    asJSON: -> @data
    copy: -> new RDBPrimitive @data

    union: -> throw new RuntimeError "Required type: array but found #{typeof @asJSON()}."
    count: -> throw new RuntimeError "LENGTH argument must be an array."
    distinct: -> throw new RuntimeError "Required type: array but found #{typeof @asJSON()}."

    not: -> not @data

    eq: (other) ->
        # We are not checking for prototype
        other_value = other.asJSON()
        if typeof @data isnt typeof other_value
            return false
        else if Object.prototype.toString.call(@data) is '[object Array]' and Object.prototype.toString.call(other_value) isnt '[object Array]'
            return false
        else if Object.prototype.toString.call(other_value) is '[object Array]' and Object.prototype.toString.call(@data) isnt '[object Array]'
            return false

        # The two variables have the same type
        if typeof @data is 'number' or typeof @data is 'string' or typeof @data is 'boolean' or typeof @data is 'undefined'
            return @data is other_value
        else if Object.prototype.toString.call(@data) is '[object Array]'
            # The two variables are arrays
            if @data.length isnt other_value.length
                return false
            else
                for value, i in @data
                    if @eq(@data[i], other_value[i]) is false
                        return false
            return true
        else if @data is null
            return @data is other.asJSON()
        else if typeof @data is 'object'
            for own key, valie of @data
                if other_value[key] is undefined
                    return false
            for own key, valie of other_value
                if @eq(@data[key], other_value[key]) is false
                    return false
            return true

        @data is other.asJSON()
    lt: (other) -> @data <  other.asJSON()
    le: (other) -> @data <= other.asJSON()
    gt: (other) -> @data >  other.asJSON()
    ge: (other) -> @data >= other.asJSON()

    add: (other) ->
        if typeof @data isnt typeof other.asJSON()
            throw new RuntimeError "Can only ADD numbers with numbers and arrays with arrays"
        if typeof @data isnt 'number' and Object.prototype.toString.call(@data) isnt '[object Array]'
            throw new RuntimeError "Can only ADD numbers with numbers and arrays with arrays"

        @data + other.asJSON()
    sub: (other) -> @data - other.asJSON()
    mul: (other) -> @data * other.asJSON()
    div: (other) -> @data / other.asJSON()
    mod: (other) -> @data % other.asJSON()


class RDBObject extends RDBJson
    asJSON: ->
        obj = {}
        for own k,v of @
            obj[k] = v.asJSON()
        return obj

    # Needed to prevent modification of table rows
    copy: ->
        result = new RDBObject
        for own k,v of @
            result[k] = v.copy()
        return result

    eq: (other) ->
        ((other[k]? && v.eq other[k]) for own k,v of @).reduce (a,b) -> a&&b

    merge: (other) ->
        self = @copy()
        for own k,v of other
            self[k] = v
        return self

    pick: (attrs) ->
        self = @copy()
        result = new RDBObject
        for k in attrs
            if self[k] is undefined
                throw new RuntimeError "Attempting to pick missing attribute #{k} from data:\n#{DemoServer.prototype.convertToJSON(self)}"
            result[k] = self[k]
        return result

    unpick: (attrs) ->
        self = @copy()
        for k in attrs
            delete self[k]
        return self