class GcalDaemon
  def initialize(email, password, room_id)
    @cal_service = GCal4Ruby::Service.new
    # @cal_service.debug = true
    @cal_service.authenticate(email, password)
    @room_id = room_id

    room = Room.find(room_id)

    @roominator_cal = @cal_service.calendars.find{|cal| CGI.unescape(cal.id) == Room::ROOMINATOR_CAL_ID}
    if !@roominator_cal
      raise "Could not find roominator calendar with id #{Room::ROOMINATOR_CAL_ID}"
    end
    @calendar = @cal_service.calendars.find{|cal| CGI.unescape(cal.id) == room.calendar_id}
    if !@calendar
      raise "ERROR: Could not find calendar for room #{room.room_name} with calendar id #{room.calendar_id}"
    end
    
    room.reserve_pressed = false
    room.cancel_pressed = false
    room.save!
    
    puts "Starting #{room.room_name}"
  end
  
  def run
    while true
      room = Room.find(@room_id)
      # puts "\nROOM: #{room.room_name}"
      # puts "working on room #{room.room_name} with cal #{@calendar.title}. reserve pressed: #{room.reserve_pressed}. cancel pressed: #{room.cancel_pressed}"
      begin
        events = events(@cal_service, @calendar.content_uri, {:futureevents => true, :singleevents => true}).sort_by(&:start_time)
      rescue GData4Ruby::HTTPRequestFailed => e
        puts "Room #{room.room_name}: GCal Error: #{e}"
        next
      end
      
      # Handle button presses
      if room.reserve_pressed && room.cancel_pressed
        #TODO Unexpected Error
        puts "Room #{room.room_name}: Both reserve and cancel pressed. Should not get to this point."
        # Do neither action
        room.reserve_pressed = false
        room.cancel_pressed = false
        room.save!
      elsif room.reserve_pressed
        handle_reserve_pressed(room, events)
      elsif room.cancel_pressed
        handle_cancel_pressed(room, events)
      end

      room.update_next_events(events)
      room.cancel_pressed = false
      room.reserve_pressed = false
      room.updated_at = Time.now
      room.save!
    end
  end
  
  # Assumes it has already been verified that a reservation
  # action can occur
  def handle_reserve_pressed(room, events)
    # check if should extend reso or make new
    if room.next_start && room.next_end && room.next_start < Time.now && room.next_end > Time.now
      # extend endtime of current event
      puts "Room #{room.room_name}: Extending current reso"
      #TODO may wish to extend the event for all attendees as well
      cur_event = events.find{|event| event.start_time == room.next_start && event.title == room.next_desc}
      if cur_event
        cur_event.end_time = get_end_time(cur_event.end_time, room.next_next_start)
        save(cur_event, @cal_service)
      else
        #TODO Unexpected Error
        puts "Room #{room.room_name}: Couldn't find event #{room.next_desc} at #{room.next_start} reserved by #{room.next_reserved_by}"
      end
    else
      puts "Room #{room.room_name}: Creating new reso"
      # create new reservation
      event = GCal4Ruby::Event.new(@cal_service)
      event.calendar = @roominator_cal
      event.title = Room::EVENT_TITLE
      event.where = room.room_name
      event.start_time = Time.now
      event.end_time = get_end_time(event.start_time, room.next_start)
      event.attendees = [{:name => room.room_name, :email => room.calendar_id, :role => "Attendee", :status => "Attending"}]
      event.save
      
      events.unshift(event)
    end
  end
  
  # Assumes it has already been verified that an event is occuring
  def handle_cancel_pressed(room, events)
    if room.next_start && room.next_end && room.next_start < Time.now && room.next_end > Time.now
      cur_event = events.find{|event| event.start_time == room.next_start && event.title == room.next_desc}
      if cur_event
        puts "Room #{room.room_name}: Cancelling current reso"
        cur_event.delete
        events.delete(cur_event)
        #TODO may wish to delete the event for all attendees as well
      else
        #TODO Unexpected Error
        puts "Room #{room.room_name}: Couldn't find event #{room.next_desc} at #{room.next_start} reserved by #{room.next_reserved_by}"
      end
    else
      #TODO Unexpected Error
      puts "Room #{room.room_name}: No event to cancel. Shouldn't have gotten to this point."
    end
  end
  
  def get_end_time(to_extend, next_start_time)
    end_time = to_extend + Room::EVENT_LENGTH_INCREMENT
    if next_start_time && next_start_time < end_time
      # make sure not to end an event into the start of the next event
      end_time = next_start_time
    end
    end_time
  end
end

# Replaces the calendar method events which doesn't take query args
def events(service, url, args)
  events = []
  ret = service.send_request(GData4Ruby::Request.new(:get, url, nil, nil, args))
  REXML::Document.new(ret.body).root.elements.each("entry"){}.map do |entry|
    entry = GData4Ruby::Utils.add_namespaces(entry)
    e = GCal4Ruby::Event.new(service)
    if e.load(entry.to_s)
      events << e
    end
  end
  return events
end

# Replace the event save which fails while retrieving the calendar
def save(event, service)
  ret = nil
  if event && event.exists?
    ret = service.send_request(GData4Ruby::Request.new(:put, event.edit_uri, event.to_xml))
  end
  if not ret or not event.load(ret.read_body)
    raise 'Could not save object'
  end
  return true
end

if $0 == __FILE__
  require "config/environment.rb"
  # print "Password: "
  #   system "stty -echo"
  #   password = $stdin.gets.chomp
  #   system "stty echo"
  GcalDaemon.new(ARGV.shift, ARGV.shift, ARGV.shift.to_i).run
end