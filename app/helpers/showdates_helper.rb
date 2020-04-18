module ShowdatesHelper

  def showdate_type_choices
    options_for_select([['In-theater','Tt'], ['Live stream','Tl'], ['Stream anytime','Ts']])
  end

  def showdate_seating_choices(showdate)
    if showdate.seatmap
      link_to 'Seats...', '', :class => 'btn btn-outline-primary btn-small'
    else
      content_tag 'span', 'General Admission'
    end
  end

  def time_in_words_relative_to(ed,sd)
    if (sd.month == ed.month) && (sd.day == ed.day) && (sd.year == ed.year)
      ed.strftime("%l:%M%p day of show")
    else
      ed.to_formatted_s(:showtime)
    end
  end

  def day_of_week_checkboxes(prefix)
    dow = %w[Mon Tue Wed Thu Fri Sat Sun]
    tag = ''
    dow.each_with_index do |day,i|
      idx = (i+1) % 7
      tag <<
        (content_tag('span', :class => 'hilite') do
          check_box_tag(prefix, idx, false,
            :name => "#{prefix}[]", :id => "#{prefix}_#{idx}") +
            content_tag('label', day, :for => "#{prefix}_#{idx}") 
        end)
    end
    tag.html_safe
  end


end
