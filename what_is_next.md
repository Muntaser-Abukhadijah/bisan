## Days task
### 8/Oct/2025

### 4/Oct/2025
* Fix showing the image in article pages. [:Done]
* Add new data to Bisan [:Done]
* Draft a Home Page [:in-progress]



### 27/Sep/2025
1. Update Bisan to be able to get any new data from Hasad without beaking existing data [:Done]
2. Refactoring and bug fixes [:inprogrss]


### 11/Sep/2025
1. Import all Metras data in a way that you don't need to remove eveything in database or meilisearch index.
1. Improve the articles card in order for the image to have standard size.
2. Fix the number of articles that show in one page.


### 10/Sep/2025
1. Read the 50 articles from Metras. [:Done]
2. Check if anything in Article page needs update. [:Done]
3. Consider HTML tags in the rendering. [:Done]
4. Why there are dublicate Images in the rendered page? [:Done]

### 25/Aug/2025
* Create artical model to represet artical data. [:Done]
    * Artical fields: (title, image, excerpt, author, category, publish-date) [:Done]
    * Migrte to SQLlit database. [:Done]
    * Seed data [:Done]
* Build articals view.
    * View file [:Done]
    * Build artical card. [:Done]
* Add pagination to the articals page. [:Done]
* Add internationalization support [:Done]

### 27/Aug/2025
* Search in Articals page using meilisearch [:Done]
* Add RTL. [:Done]

### 28/Aug/2025
* Build Artical body page [:Done]
* Pause to understand everthing that is exist util this point.
* Review and define list of task to be completed before adding actual data.
    * List of tasks:
        * Arabic as default language. [:Done]
        * "All articals" to. "Articals" same for Arabic.  [:Done]
        * Search bar localization (place holder, and search botton). [:Done]
        * Search highlight to be in color in "em" [:Done]
        * Also some of the items in the ToDo list. [:Done]

### 30/Aug/2025
* Author page.

### 30/Aug/2025
* Build the prompt file [:Done]
* http://127.0.0.1:3000/ defualt is english, should be Arabic [:Done]
* Author page.
    * App name get changed to author name, it shouldn't [:Done]
    * Author page should have better listing for the articals. [:Done]
    * Search bar
* Understand how things works toghter [:Done]
* Default still not english [:done]

### 01/Sep/2025
* Update the prompt file [:Done]
* Seed actual data [:Done]
* Logo [:Done]
* Nav-bar/header [:Done]

### 02/Sep/2025
* Use search bar in authros pages. [:Done]

### 03/Sep/2025
* Logo in Arabic. [:done]



## Ordered list to pick from
3. Scrapper solution - Design and requirement doc [1]
    3.1 Learn about scrapping using "Scrapfly Web Scraping Academy"
    3.2 Requirement doc and High level design
4. Scrapper solution - Scrapping metras as first step [1]


## ToDo (Item - [Priorty 1-4])
* Update articals card to When clicking on tag it should link to page shows all articas with such tag/catigrory. [4]
* Add langauge support. (I think translation support here I mean) [4]
* Lokalise—a platform that simplifies managing and editing localization files. Let’s walk through the setup. [4]
* Deploy [3]
* Handle 404 (error) routes. [2]
* Infinite scroll. [3]
* Filters. [3]
* Categories page [3]
* Logo in Arabic. [1]
* Icones for nav bar tabs [4]
* Dark/light mode. [4]
* Social media for the app [4]
* Define how data should be added from the scrapper to Bisan [1]
* To have better Logs [2]
* Standarize the size of the images in Articles page.
-----------------------------------------------------------
* List new 18 new soruces to be added. [1]
    * https://ultrapal.ultrasawt.com/
    * https://www.alzaytouna.net/
    * https://www.palestine-studies.org/ar/blogs/all2
    * https://www.palestineforum.net/category/%D9%85%D9%82%D8%A7%D9%84%D8%A7%D8%AA/
    * https://www.palestinechronicle.com/gazas-blackwater-despite-denials-us-boots-will-be-on-the-ground-in-gaza/
    * https://palinfo.com/category/opinion/
    * https://www.arab48.com/%D9%81%D9%84%D8%B3%D8%B7%D9%8A%D9%86%D9%8A%D8%A7%D8%AA/%D8%AF%D8%B1%D8%A7%D8%B3%D8%A7%D8%AA-%D9%88%D8%AA%D9%82%D8%A7%D8%B1%D9%8A%D8%B1
    * https://aljarmaq.net/
    * https://electronicintifada.net/
    * https://mondoweiss.net/ways-to-give/
    * https://www.972mag.com/
    * https://babelwad.com/

* Metrics. [4]
* Project name and domain name. [4]
* Unit tests. [6]











## Bugs:
* When you go to wrong path, you don't get redirected to 404.
* Create excerpt for articles that does not have excerpt

## Ideas:
* Collect comdy shows about palestine.
* قسم وصايه الشهداء
* منشورات 
* قسم الاسره
* فسم المشاهير الداعمين
* جنود الاحتلال