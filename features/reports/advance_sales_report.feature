Feature: generate advance sales reports

  As the bookkeeper
  So that I can get accurate info for royalty applications and grants
  I want to generate advance sales reports for arbitrary sets of shows

Background:

  Given I am logged in as box office manager
  And   the following shows exist:
  | name      | opening_date | closing_date | house_capacity |
  | Hamlet    |   2010-01-01 |   2010-01-31 |             50 |
  | King Lear |   2012-01-20 |   2012-01-31 |             50 |
  And   a performance of "Hamlet" on "January 21, 2010, 8:00pm"
  And   a performance of "King Lear" on "January 23, 2012, 8:00pm"
  And   a performance of "King Lear" on "January 24, 2012, 8:00pm"
  And   I am on the reports page
  
Scenario: generate sales report for two shows


  When  I select "Hamlet (Jan - Feb 2010)" from "shows"
  And   I select "King Lear (Jan - Feb 2012)" from "shows"
  And   I press "advance_sales"
  Then  I should see "1 performance" within the div for the show with name "Hamlet"
  And   I should see "2 performances" within the div for the show with name "King Lear"
