require 'sinatra'
require 'json'
require 'securerandom'
require 'rufus-scheduler'


class KeyServerApp
	@@key_database = Hash.new(nil)
	@@blocked_keys = Hash.new(nil)
	@@key_count = 0
	@@blocked_count = 0

	class Key
		attr_accessor :update_time
		attr_accessor :value

		def initialize(value, time)
			@value = value
			@update_time = time
		end
	end

	def status
		status = ""
		puts "[#{Time.now}] In Status"
		@@key_database.each do |key, value|
			status += "Key : #{key}		Value : #{value.update_time}	#{value.value}<br>"
		end
		status += "Blocked Keys: #{@@blocked_keys}<br>"
		status += "Keys count #{@@key_count}<br>"
		status += "Blocked Keys count #{@@blocked_count}<br>"
		status
	end

	def generate
		puts "[#{Time.now}] In generate"
		random_string = SecureRandom.hex
		while @@key_database[random_string] != nil 
			random_string = SecureRandom.hex
		end
		puts "[#{Time.now}] Random Value #{random_string}"
		key = Key.new(random_string, Time.now)
		@@key_database[random_string] = key
		@@key_count += 1
		puts "[#{Time.now}] Key count #{@@key_count}"
		""
	end

	def getkey
		random_key = ""
		puts "[#{Time.now}] In getkey"
		if @@blocked_count == @@key_count
			puts "[#{Time.now}] No keys available. Returning 404"
		else
			random_key = @@key_database.keys.sample(1)[0]
			puts "[#{Time.now}] Got the random key #{random_key}"
			while @@blocked_keys[random_key] != nil
				random_key = @@key_database.keys.sample(1)[0]
			end
			@@key_database[random_key].update_time = Time.now
			@@blocked_keys[random_key] = Time.now
			@@blocked_count += 1
		end
		random_key
	end

	def unblock(key_val)
		puts "[#{Time.now}] Unblock request for #{key_val}"
		if @@blocked_keys[key_val] != nil
			@@blocked_keys.delete(key_val)
			@@blocked_count -= 1
			success = true
		else
			success = false
		end
		success
	end

	def keep_alive(key_val)
		puts "[#{Time.now}] Keep alive request for #{key_val}"
		if @@key_database[key_val] != nil
			@@key_database[key_val].update_time = Time.now
			success = true
		else
			success = false
		end
		success
	end

	def delete(key_val)
		puts "[#{Time.now}] Delete request for #{key_val}"
		if @@key_database[key_val] != nil
			@@key_database.delete(key_val)
			@@key_count -= 1
			if @@blocked_keys[key_val] != nil
				@@blocked_keys.delete(key_val)
				@@blocked_count -= 1
			end
			success = true
		else
			success = false
		end
		success
	end

	def get_blocked_keys
		@@blocked_keys
	end

	def get_keys
		@@key_database
	end	
end


key_server = KeyServerApp.new

set :port, 8080

# REST Endpoints
get '/status' do
	status 200
	key_server.status
end

get '/generate' do
	status 201
	key_server.generate
end

get '/get-key' do
	key = key_server.getkey
	if key == ""
		status 404
	else
		status 200
		key
	end
end

post '/update-key' do
	request.body.rewind
	data = JSON.parse(request.body.read)
	if data.has_key?("key")	
		is_updated = key_server.keep_alive data["key"]
		if is_updated
			status 200
			"Key updated successfully!" 
		else
			status 204
			"Invalid Key"
		end
	else
		status 204
		"Please pass the valid key in POST parameters"
	end
end

delete '/delete-key' do
	request.body.rewind
	data = JSON.parse(request.body.read)
	if data.has_key?("key")	
		is_deleted = key_server.delete data["key"]
		if is_deleted
			status 200
			"Key deleted successfully!" 
		else
			status 204
			"Invalid Key"
		end
	else
		status 204
		"Please pass the valid key in POST parameters"
	end	
end

post '/unblock-key' do
	request.body.rewind
	data = JSON.parse(request.body.read)
	if data.has_key?("key")
		is_unblocked = key_server.unblock data["key"]
		if is_unblocked
			status 200
			"Key unblocked successfully!" 
		else
			status 204
			"Invalid Key"
		end
	else
		status 204
		"Please pass the valid key in POST parameters"
	end
end

#Task Scheduling
scheduler = Rufus::Scheduler.new

scheduler.every '60s' do
	cur_time = Time.now
	
	# Release the blocked keys after every 60 seconds
	to_release = key_server.get_blocked_keys.select{|key, val| ((cur_time - val) / 60) > 1}
	to_release.each{|key, value| key_server.unblock key}
	puts "[#{Time.now}] Released #{to_release.keys.length} keys"

	# Delete the inactive keys after every 5 minutes
	to_delete = key_server.get_keys.select{|key, val| ((cur_time - val.update_time) / 60) > 5}
	to_delete.each{|key, value| key_server.delete key}
	puts "[#{Time.now}] Delete #{to_delete.keys.length} keys"
end
